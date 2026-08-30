-- Lascivious Factions System - player-facing panel.
-- A custom ISPanel window (branded header, full-height animated sidebar nav with
-- a gliding accent indicator, rounded/shadowed body) whose right-side content
-- area is rebuilt per section. The whole panel recolours to the player's faction
-- (UI.setAccent in :showSection). Reads only from the replicated registry
-- (FF.getData()) and drives the framework through the same sendClientCommand
-- intents the /ff chat commands already use.
--
-- All visual language (tokens, rounded-corner/shadow/animation helpers, and the
-- FFButton/FFCard/FFBar/FFBadge/FFHeader/FFToggle widgets) lives in
-- LFS_UI. We require it directly: name-based auto-load runs
-- alphabetically and would load "_UI" AFTER this file, leaving FF.UI/FFButton/etc.
-- nil when the classes below are built. The rounded/animated look is our own
-- reimplementation inspired by the Aegis admin panel (no Aegis code is imported).

require "LFS_Shared"
require "LFS_Claims"
require "LFS_TileToolAPI"
require "LFS_UI"
require "LFS_ClaimMap"
require "LFS_Upgrades"
require "LFS_VehicleGuard"
require "LFS_Hunter"
require "LFS_VehiclePanel"
require "Vehicles/ISUI/ISVehicleMenu"
require "LFS_Danger"

local FF = LasciviousFactionsSystem
local UI = FF.UI

print("[LFS] panel lua loaded")

-- True if any of the passed ISTextEntryBox widgets is currently focused. Used by the
-- Escape-to-close handlers so they don't close a window out from under an active text
-- field (only the current tab's entries exist; others are nil). Declared here, above
-- every user, so both FactionCreateDialog and LasciviousFactionsSystemPanel can see it -- a
-- `local function` declared lower would be an out-of-scope nil for the earlier class.
-- select() (not ipairs) so nil holes don't cut the loop short; pcall so a removed
-- widget can't error.
local function anyEntryFocused(...)
    for i = 1, select("#", ...) do
        local e = select(i, ...)
        if e then
            local ok, f = pcall(function() return e:isFocused() end)
            if ok and f then return true end
        end
    end
    return false
end

-- Shared with the stall window. Clips the pane AND installs the wheel handler -- see
-- UI.setupScrollPane for why both belong in one call. passWheel goes on every text entry
-- so it doesn't eat the wheel on the way past.
local setupScrollPane = UI.setupScrollPane
local passWheel = UI.passWheel

-- Six sidebar sections. Roles folds into Members (a pane
-- toggled from its header row) and the four faction-vs-faction views live behind
-- the Factions section's sub-tab strip -- see FACTION_SUBTABS / SECTION_ALIAS.
-- No per-row icon: the redesign's nav is label + state dot (see :prerender). The
-- ic_* set is still used by the buttons, badges and notices throughout the tabs.
--
-- `group` splits the flat list into the two questions a player arrives with -- what
-- is MY faction doing, what is everyone else doing -- with Settings and Help pinned
-- to the sidebar's bottom (group `footer`) since they are destinations you go
-- looking for, not ones you scan past.
local SECTIONS = {
    { key = "overview", label = "Overview", group = "My Faction" },
    { key = "members",  label = "Members",  group = "My Faction" },
    { key = "claims",   label = "Claims",   group = "My Faction" },
    -- Labels written directly in Portuguese (unlike their English siblings above,
    -- which rely on FF.tr's auto-generated KEYS table): FF.tr gracefully returns
    -- unmatched text unchanged, so a pre-resolved PT string here shows correctly
    -- WITHOUT AN ACCENT -- "Aprimoramentos"/"Tributo" happen to have none, which
    -- is the only reason this ever looked safe. It is not: drawRow's plain
    -- FF.tr(sec.label) draw call is the same raw-literal-through-native-draw
    -- path proven broken for accented characters elsewhere this session (see
    -- STATS in LFS_Territory.lua). Any FUTURE accented label here needs the
    -- labelKey/FF.text treatment "Veículos" below uses -- do not add another
    -- bare accented literal assuming this comment's old claim still holds.
    { key = "upgrades", label = "Aprimoramentos", group = "My Faction" },
    { key = "vehicles", label = "Veículos", labelKey = "UI_LFS_SectionVehicles", group = "My Faction" },
    { key = "tribute",  label = "Tributo",  group = "My Faction" },
    { key = "factions", label = "Factions", group = "World" },
    { key = "settings", label = "Settings", group = "footer" },
    { key = "help",     label = "Help",     group = "footer" },
    -- Gated (FF.getOptions().debugToolsEnabled -- true singleplayer + the Debug
    -- sandbox flag, see LFS_Shared.lua) -- filtered out of visibleSections()
    -- entirely unless both are true. Never available in real MP, by construction.
    { key = "debug",    label = "Debug",    group = "footer" },
}

local FACTION_SUBTABS = {
    { key = "directory",   label = "Directory" },
    { key = "relations",   label = "Relations" },
    { key = "leaderboard", label = "Leaderboard" },
    { key = "raid",        label = "Raid" },
}

-- Sub-tabs of the Debug section -- same FFSubTabs strip as Factions above,
-- see populateDebug/onDebugSubTab. "Bem-estar" is the pre-existing content
-- (faction power + the wellbeing snapshot tools); "Veículos" is the debug view
-- for the workshop upgrade's vehicle auto-maintenance (LFS_Server.lua's
-- workshopMaintTick).
local DEBUG_SUBTABS = {
    { key = "wellbeing", label = "Bem-estar" },
    { key = "vehicles",  label = "Veículos", labelKey = "UI_LFS_DebugSubTabVehicles" },
    { key = "hunter",    label = "Caçador",  labelKey = "UI_LFS_DebugSubTabHunter" },
}

-- The pre-redesign section keys still name real destinations -- other files, the
-- in-panel "Manage claim" jump and the roles list all call showSection() with
-- them. Map each onto its new home (section + the sub-view to open there) rather
-- than hunting down every caller.
local SECTION_ALIAS = {
    roles       = { section = "members",  showRoles = true },
    relations   = { section = "factions", subTab = "relations" },
    leaderboard = { section = "factions", subTab = "leaderboard" },
    raid        = { section = "factions", subTab = "raid" },
}

-- Widened from 132 for "Aprimoramentos" -- the longest nav label -- which was
-- crowding the sidebar's right edge (nav labels are not clipped/ellipsized, see
-- drawRow below). WINDOW_WIDTH grew by roughly the same amount so the content
-- area doesn't shrink to make room.
local SIDEBAR_WIDTH = 156
-- Wider/taller than the text-only tabs strictly need, so the Claims tab's
-- embedded map has room to drag on. The other tabs size off self.content width
-- and reflow safely. Bumped from 800x600 (2026-08-23, "um pouquinho maior") --
-- still comfortably under initialGeometry's scale-down floor on any normal
-- desktop resolution, see .toggle() below.
local WINDOW_WIDTH = 900
local WINDOW_HEIGHT = 680

-- ---------------------------------------------------------------------------
-- Intent sender (each client file in this mod keeps its own copy of this helper
-- rather than sharing a require -- matches LFS_Client.lua)
-- ---------------------------------------------------------------------------
local function send(command, args)
    sendClientCommand(getPlayer(), FF.MODULE, command, args or {})
end

-- ---------------------------------------------------------------------------
-- Shared formatting helpers. Declared here, above every user: a `local function`
-- declared further down would be an out-of-scope nil for the section builders
-- above it (Lua resolves the earlier reference as a global, not an upvalue).
-- ---------------------------------------------------------------------------
-- Moved to UI.wrapText so the stall window can share one implementation; kept as a
-- file-local alias because ~40 call sites below use the short name.
local wrapText = UI.wrapText

-- The initials square that opens every list row: a faction- or player-derived colour
-- with up to two initials on it. Gives a list a column for the eye to run down, and
-- makes the same entity recognisable across the roster, the directory and the map,
-- which all derive their colour from the same name. Returns the x to write text at.
local function drawRowAvatar(el, x, y, h, label, color)
    local sz = UI.fh(UI.font.body) + 8
    local ay = y + math.floor((h - sz) / 2)
    local ac = color or UI.factionColor(label)
    UI.roundRect(el, x, ay, sz, sz, 6, 1.0, ac)
    local on = UI.readableOn(ac)
    el:drawTextCentre(UI.initials(label), x + math.floor(sz / 2),
        ay + math.floor((sz - UI.fh(UI.font.small)) / 2), on.r, on.g, on.b, 1.0, UI.font.small)
    return x + sz + 10
end

-- Draws a pill in the row's right-hand slot and returns its left edge, so the name
-- beside it can be clipped against something real rather than a guessed width.
-- A drawn pill rather than an FFBadge child: list rows are painted, not built.
local function drawRowPill(el, x2, y, h, text, color, filled)
    local ph = UI.badgeH()
    local pw = UI.tw(UI.font.small, text) + 16
    local px, py = x2 - pw, y + math.floor((h - ph) / 2)
    if filled then
        UI.roundRect(el, px, py, pw, ph, math.floor(ph / 2), 0.20, color)
    else
        UI.roundFrame(el, px, py, pw, ph, math.floor(ph / 2), 1.0, color, nil)
    end
    el:drawText(text, px + 8, py + math.floor((ph - UI.fh(UI.font.small)) / 2),
        color.r, color.g, color.b, 1.0, UI.font.small)
    return px
end

-- Add a label inside an FFCard (cardLabel in populateSettings is a local closure; this
-- is the shared file-local version used by every other card builder in this file).
local function cardText(card, lx, ly, text, color, font)
    text = FF.tr(text)
    local c = color or UI.color.text
    font = font or UI.font.body
    -- Height from the font, not a literal: ISLabel does not clip on it, but under-
    -- reporting the box is what blinds `/ff admin uitest`'s escapes-y check.
    local l = ISLabel:new(lx, ly, UI.fh(font), text, c.r, c.g, c.b, 1.0, font, true)
    l:initialise(); card:addChild(l)
    return l
end

-- Creation uses the founder's CURRENT CHARACTER score. Prefer the live vanilla
-- counters for the local player, exactly like the server's createFaction handler
-- does immediately before accepting the request; fall back to the replicated
-- snapshot only when those methods are unavailable during early UI startup.
-- Returning one shared answer keeps the overview, dialog and click guards from ever
-- disagreeing about whether the button should be active.
local function factionCreationRequirement()
    local opts = FF.getOptions()
    local required = math.max(0, tonumber(opts.minPersonalScoreToCreateFaction) or 0)
    local player = getPlayer()
    local username = player and player:getUsername() or nil
    local score = username and FF.playerScore(username, opts) or 0

    if player and player.getZombieKills and player.getHoursSurvived
        and not (player.isDead and player:isDead()) then
        local ok, live = pcall(function()
            local kills = math.max(0, math.floor(tonumber(player:getZombieKills()) or 0))
            local hours = math.max(0, tonumber(player:getHoursSurvived()) or 0)
            return kills * opts.pointsPerZombieKill + hours * opts.pointsPerHourSurvived
        end)
        if ok then score = math.max(0, tonumber(live) or 0) end
    elseif player and player.isDead and player:isDead() then
        score = 0
    end

    return score >= required, score, required
end

-- Keep fractional sandbox weights readable without exposing long floating-point
-- tails (for example 413.3546359235). Whole scores stay whole; otherwise show one
-- decimal, which is enough for a clear progress indicator.
local function shortScore(value)
    value = math.max(0, tonumber(value) or 0)
    local rounded = math.floor(value * 10 + 0.5) / 10
    if math.abs(rounded - math.floor(rounded + 0.5)) < 0.0001 then
        return tostring(math.floor(rounded + 0.5))
    end
    return string.format("%.1f", rounded)
end

-- Debug snapshot number formatting (see populateDebug): a 0..1-range stat (STRESS,
-- HUNGER, etc.) needs more decimal places to show any movement at all than a
-- 0..100 one, so the precision follows the stat's own max rather than one fixed
-- format for every row.
local function formatSnapshotValue(v, maxRange)
    v = tonumber(v) or 0
    if maxRange and maxRange <= 1 then return string.format("%.4f", v) end
    return string.format("%.2f", v)
end

-- Percent CHANGE relative to the before value (not percent-of-range -- this is
-- "how much did it move", the same quantity the design brief's own example
-- format asks for). A zero before-value has no meaningful percent change, so
-- that case is called out rather than shown as a fake 0% or a divide-by-zero.
local function formatPctChange(before, after)
    before, after = tonumber(before) or 0, tonumber(after) or 0
    if before == 0 then return (after == 0) and "0%" or "-" end
    local pct = (after - before) / before * 100
    -- A real but tiny change (e.g. a 0.03-point move on a 93-point stat) rounds to
    -- "+0.0%" at one decimal, which reads as "not working" rather than "working,
    -- just a small step" -- exactly the confusion reported. Fall back to 3 decimals
    -- ONLY for the genuinely-nonzero-but-rounds-away case, so the 1-decimal format
    -- stays clean everywhere it's already informative.
    if pct ~= 0 and math.abs(pct) < 0.05 then
        return string.format("%+.3f%%", pct)
    end
    return string.format("%+.1f%%", pct)
end

-- ---------------------------------------------------------------------------
-- Small panel-local widgets built on the toolkit tokens.
-- ---------------------------------------------------------------------------

-- StatRow: a "label ......... value" line with a leading status dot, used inside
-- the Overview / Claims cards.
local StatRow = ISPanel:derive("FFStatRow")
function StatRow:new(x, y, width, label, value, dotColor)
    label, value = FF.tr(label), FF.tr(value)
    local o = ISPanel:new(x, y, width, UI.fh(UI.font.body) + 2)
    setmetatable(o, self); self.__index = self
    o.background = false
    o.labelText = label
    o.valueText = value
    o.dot = dotColor
    return o
end
function StatRow:prerender()
    local w, h = self:getWidth(), self:getHeight()
    local c = UI.color
    local cy = math.floor((h - UI.fh(UI.font.body)) / 2)
    if self.dot then
        self:drawRect(0, math.floor(h / 2) - 3, 6, 6, 1.0, self.dot.r, self.dot.g, self.dot.b)
    end
    self:drawText(self.labelText, 14, cy, c.dim.r, c.dim.g, c.dim.b, 1.0, UI.font.body)
    self:drawTextRight(self.valueText, w, cy, c.text.r, c.text.g, c.text.b, 1.0, UI.font.body)
end

-- Notice: a single-line strip with a coloured left accent + optional icon, used
-- for raid status and the "not in a faction" hint.
local Notice = ISPanel:derive("FFNotice")
function Notice:new(x, y, width, text, color, icon)
    text = FF.tr(text)
    local o = ISPanel:new(x, y, width, UI.rowH(UI.font.body))
    setmetatable(o, self); self.__index = self
    o.background = false
    o.text = text
    o.color = color or UI.color.dim
    o.icon = icon
    return o
end

-- Live requirement summary placed directly below the creation action. It owns the
-- button's enabled state as well as the explanation, so a player never sees an
-- active-looking button beside text saying creation is blocked. The score is read
-- every frame from the character, making kills/survival progress visible without
-- waiting for the next replicated GlobalModData refresh.
local CreationRequirement = ISPanel:derive("LFSCreationRequirement")

function CreationRequirement:new(x, y, width, createButton)
    local bodyH = UI.lineH(UI.font.body)
    local smallH = UI.lineH(UI.font.small)
    local o = ISPanel:new(x, y, width, bodyH + smallH * 2 + 4)
    setmetatable(o, self); self.__index = self
    o.background = false
    o.createButton = createButton
    return o
end

function CreationRequirement:prerender()
    local allowed, score, required = factionCreationRequirement()
    local button = self.createButton
    if button then
        button:setEnable(allowed)
        button.tooltip = allowed and nil or FF.text("UI_LFS_CreateRequirementTooltip",
            "Your character does not have the score required to create a faction.")
    end

    local color = allowed and UI.color.good or UI.color.bad
    local status = allowed
        and FF.text("UI_LFS_CreateRequirementMet", "You meet the requirements to create a faction.")
        or FF.text("UI_LFS_CreateRequirementMissing", "You do not meet the requirements to create a faction yet.")
    local progress = FF.text("UI_LFS_CreateScoreProgress", "Character score: %s / %s",
        shortScore(score), shortScore(required))

    self:drawText(UI.fit(UI.font.body, status, self:getWidth()), 0, 0,
        color.r, color.g, color.b, 1.0, UI.font.body)
    local py = UI.lineH(UI.font.body)
    self:drawText(UI.fit(UI.font.small, progress, self:getWidth()), 0, py,
        UI.color.text.r, UI.color.text.g, UI.color.text.b, 1.0, UI.font.small)

    if not allowed then
        local hint = FF.text("UI_LFS_CreateRequirementHint",
            "Sobreviva por mais tempo e mate zumbis para conseguir mais pontos.")
        self:drawText(UI.fit(UI.font.small, hint, self:getWidth()), 0,
            py + UI.lineH(UI.font.small), UI.color.dim.r, UI.color.dim.g,
            UI.color.dim.b, 1.0, UI.font.small)
    end
end
function Notice:prerender()
    local w, h = self:getWidth(), self:getHeight()
    local col = self.color
    UI.roundRect(self, 0, 0, w, h, 6, 0.12, col)
    self:drawRect(0, 5, 3, h - 10, 1.0, col.r, col.g, col.b)
    local tx = 12
    if self.icon then
        local isz = math.min(16, h - 8)
        UI.drawIcon(self, self.icon, 10, math.floor((h - isz) / 2), isz, col)
        tx = 34
    end
    -- Trim rather than overflow: the text carries faction names and MOTDs, so its
    -- length is player-controlled and unbounded.
    self:drawText(UI.fit(UI.font.body, self.text, w - tx - 10), tx, math.floor((h - UI.fh(UI.font.body)) / 2),
        UI.color.text.r, UI.color.text.g, UI.color.text.b, 1.0, UI.font.body)
end



-- ClaimAreaList: the Claims tab's list of separate logical claim areas. Reads the
-- embedded map's WORKING SET live every frame (like the capacity bar) rather than
-- rendering a snapshot: rects are added by dragging on the map, so a snapshot
-- would go stale the instant the player draws, and rebuilding the tab from inside
-- a drag is not safe. Click a row to zoom the map to it, the access badge to open
-- the access dialog, or the x to drop it.
-- One line of text plus padding; grows with the font like every other row here.
local function areaRowH() return UI.rowH(UI.font.small) + 4 end
local AREA_BADGE_W = 50

-- Short label + colour for an area's access level. Private is deliberately dim: it
-- is the default and the overwhelmingly common case, so it should recede.
local AREA_BADGE = {
    private = { text = "Private", key = "dim" },
    allies  = { text = "Allies",  key = "accent" },
    public  = { text = "Public",  key = "public" },
}

local function areaBadgeSpec(rect)
    return AREA_BADGE[FF.areaAccess(rect)] or AREA_BADGE.private
end

local ClaimAreaList = ISPanel:derive("FFClaimAreaList")
function ClaimAreaList:new(x, y, width, height, map, canEdit)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self); self.__index = self
    o.background = false
    o.map = map
    o.canEdit = canEdit and true or false   -- no delete/access affordance for a viewer
    o.rowRects = {}
    return o
end
function ClaimAreaList:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    local AREA_ROW_H = areaRowH()
    local map = self.map
    self.rowRects = {}
    if not map then return end

    local groups = map:areaGroups()
    local opts = FF.getOptions()
    local rowCount = #groups
    local count = FF.claimComponentCount(map.rects)
    local maxCount = FF.maxClaimAreas(FF.factionScore(map.faction, opts), opts)
    self:drawText(FF.text("UI_LFS_ClaimAreasCount", "CLAIM AREAS  %d / %d", count, maxCount), 0, 0,
        c.accent.r, c.accent.g, c.accent.b, 1.0, UI.font.small)
    local top = UI.fh(UI.font.small) + 6

    if rowCount == 0 then
        self:drawText(FF.text("UI_LFS_NoClaimAreas", "None yet -- use Draw claim."), 0, top,
            c.faint.r, c.faint.g, c.faint.b, 1.0, UI.font.small)
        return
    end

    -- Only draw what fits; the rect cap is a sandbox option an admin can raise.
    local maxRows = math.floor((h - top) / AREA_ROW_H)
    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver()
    for i = 1, math.min(rowCount, maxRows) do
        local group = groups[i]
        local r = group.rect
        local ry = top + (i - 1) * AREA_ROW_H
        local hovered = over and my >= ry and my < ry + AREA_ROW_H - 2
        local xSize = self.canEdit and 18 or 0
        local xx = w - xSize - 2
        local overX = hovered and self.canEdit and mx >= xx
        UI.roundFrame(self, 0, ry, w, AREA_ROW_H - 2, 6, 1.0,
            hovered and c.borderH or c.border, hovered and c.cardHi or c.card)

        -- Pending (unsubmitted) areas carry the accent, matching how the map
        -- itself paints r.new rectangles brighter than the committed claim.
        local dotCol = group.new and c.accent or (map.factionCol or c.accent)
        UI.roundRect(self, 8, ry + math.floor((AREA_ROW_H - 2) / 2) - 3, 6, 6, 3, 1.0, dotCol)

        local textY = ry + math.floor((AREA_ROW_H - 2 - UI.fh(UI.font.small)) / 2)

        -- Access badge sits between the label and the delete X. Shown to EVERY member,
        -- not just editors -- knowing part of your claim is open to outsiders matters
        -- whether or not you're the one who can change it -- but only an editor gets it
        -- as a hit zone (see rowRects below).
        local access = FF.areaAccess(r)
        local badgeX = xx - AREA_BADGE_W - 4
        local spec = areaBadgeSpec(r)
        local bc = (spec.key == "public") and UI.publicClaimColor
            or (spec.key == "accent" and c.accent or c.dim)
        local overBadge = hovered and self.canEdit and mx >= badgeX and mx < xx
        -- Private stays a flat label; an OPENED area gets a filled pill, so a claim
        -- with something open to outsiders is obvious at a glance.
        if access ~= "private" then
            UI.roundRect(self, badgeX, ry + 5, AREA_BADGE_W, AREA_ROW_H - 12, 5,
                overBadge and 0.42 or 0.28, bc)
        elseif overBadge then
            UI.roundRect(self, badgeX, ry + 5, AREA_BADGE_W, AREA_ROW_H - 12, 5, 0.5, c.panel2)
        end
        local bt = (access == "private") and (overBadge and c.text or c.faint) or bc
            self:drawTextCentre(FF.tr(spec.text), badgeX + math.floor(AREA_BADGE_W / 2), textY,
            bt.r, bt.g, bt.b, 1.0, UI.font.small)

        local label = FF.text("UI_LFS_ClaimAreaTiles", "%d quadrados", group.area)
        self:drawText(UI.fit(UI.font.small, label, badgeX - 24), 20, textY,
            c.text.r, c.text.g, c.text.b, 1.0, UI.font.small)

        if self.canEdit then
            local xc = overX and c.bad or c.faint
            self:drawText("X", xx + 5, textY, xc.r, xc.g, xc.b, 1.0, UI.font.small)
        end
        -- Three hit zones, left to right: focus | access badge | delete. Both
        -- thresholds are math.huge for a viewer, so every click falls through to
        -- "focus this area".
        self.rowRects[#self.rowRects + 1] = {
            index = i, y = ry, h = AREA_ROW_H - 2,
            xBadge = self.canEdit and badgeX or math.huge,
            xFrom = self.canEdit and xx or math.huge,
        }
    end
end
function ClaimAreaList:onMouseDown(x, y) return true end
function ClaimAreaList:onMouseUp(x, y)
    for _, r in ipairs(self.rowRects) do
        if y >= r.y and y < r.y + r.h then
            getSoundManager():playUISound("UIActivateButton")
            if x >= r.xFrom then self.map:removeIndex(r.index)
            elseif x >= r.xBadge then FactionAreaAccessDialog.open(self.map, r.index)
            else self.map:focusRect(r.index) end
            return true
        end
    end
    return false
end

-- RolePermRow: a clickable "permission label ....... [x]" row for the Roles tab.
-- Derives ISButton so it handles clicks; draws its own label + checkbox. When
-- read-only (no onclick) it just shows state.
local RolePermRow = ISButton:derive("FFRolePermRow")
function RolePermRow:new(x, y, width, height, label, on, target, onclick)
    label = FF.tr(label)
    local o = ISButton:new(x, y, width, height or (UI.fh(UI.font.body) + 8), "", target, onclick)
    setmetatable(o, self); self.__index = self
    o.label = label
    o.on = on
    o.font = UI.font.body
    o.hoverT = 0
    o.knobT = on and 1 or 0
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
    return o
end
function RolePermRow:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    local clickable = (self.onclick ~= nil)
    local hover = clickable and self:isMouseOver()
    self.hoverT = UI.glide(self.hoverT or 0, hover and 1 or 0, 0.3)
    if self.hoverT > 0.01 then
        UI.roundRect(self, 0, 0, w, h, 6, 0.5 * self.hoverT, c.panel2)
    end
    local cy = math.floor((h - UI.fh(self.font)) / 2)
    local txt = clickable and c.text or c.dim
    -- Fitted: the Members tab hosts these in a ~250px column, narrower than the
    -- old full-width Roles tab, so a long permission label would run under the switch.
    self:drawText(UI.fit(self.font, self.label, w - 44), 6, cy, txt.r, txt.g, txt.b, 1.0, self.font)
    -- Sliding on/off switch on the right (dimmer when the row is read-only).
    local a = clickable and 1 or 0.6
    local tw, th = 32, 16
    local sx, sy = w - tw - 2, math.floor((h - th) / 2)
    UI.roundRect(self, sx, sy, tw, th, math.floor(th / 2), a, c.track)
    self.knobT = UI.glide(self.knobT or 0, self.on and 1 or 0, 0.3)
    if self.knobT > 0.01 then
        UI.roundRect(self, sx, sy, tw, th, math.floor(th / 2), self.knobT * a, c.accent)
    end
    local kd = th - 4
    local kx = sx + 2 + (tw - 4 - kd) * self.knobT
    local kc = self.knobT > 0.5 and UI.readableOn(c.accent) or c.text
    local dot = UI.icon("ui_dot")
    if dot then
        self:drawTextureScaled(dot, kx, sy + 2, kd, kd, a, kc.r, kc.g, kc.b)
    else
        self:drawRect(kx, sy + 2, kd, kd, a, kc.r, kc.g, kc.b)
    end
end
function RolePermRow:render() end

-- ColorSwatch: a clickable colour square for the Settings accent-colour picker.
-- `col` is an {r,g,b} table, or nil for the "Auto" (name-derived) option.
local ColorSwatch = ISButton:derive("FFColorSwatch")
function ColorSwatch:new(x, y, size, col, selected, target, onclick)
    local o = ISButton:new(x, y, size, size, "", target, onclick)
    setmetatable(o, self); self.__index = self
    o.col = col
    o.selected = selected
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
    return o
end
function ColorSwatch:prerender()
    local w, h = self:getWidth(), self:getHeight()
    local c = UI.color
    local b = self.selected and c.accent or (self:isMouseOver() and c.borderH or c.border)
    local inset = self.selected and 2 or 1
    -- Ring in the border/accent colour, colour fill inset over it.
    UI.roundRect(self, 0, 0, w, h, 5, 1.0, b)
    local fill = self.col or c.panel2
    UI.roundRect(self, inset, inset, w - 2 * inset, h - 2 * inset, math.max(1, 5 - inset), 1.0, fill)
    if not self.col then
        self:drawTextCentre("A", math.floor(w / 2), math.floor((h - UI.fh(UI.font.small)) / 2),
            c.text.r, c.text.g, c.text.b, 1.0, UI.font.small)
    end
end
function ColorSwatch:render() end

-- HudIcon: persistent emblem button. Tints the shipped emblem to the player's
-- faction colour and turns its ring red while under raid -- read live every frame
-- from the replicated registry, so no separate ticker is needed.
--
-- Used in two places, so everything below is sized from the button's own bounds
-- rather than hardcoded: the top-right corner (square) and the vanilla left
-- sidebar (non-square, and its size follows the sidebar-size option).
-- Published as FF.HudIcon (not a bare global -- too generic a name to leak) so
-- LFS_VanillaUI.lua can build one for the sidebar.
local HudIcon = ISButton:derive("FFHudIcon")
FF.HudIcon = HudIcon
function HudIcon:new(x, y, width, height)
    local o = ISButton:new(x, y, width, height, "", nil, function() LasciviousFactionsSystemPanel.toggle() end)
    setmetatable(o, self); self.__index = self
    -- Other sidebar mods commonly shrink ISEquippedItem by considering only children
    -- whose Type is exactly "ISButton". A derived type is still drawn below the
    -- shrunken parent, but parent hit-testing makes that visible button impossible to
    -- click. Advertise the native type while retaining HudIcon's metatable behaviour.
    o.Type = "ISButton"
    o.internal = "LFSFACTION"
    -- A COPY, not UI.color.border itself. Sidebar mods fade their siblings by writing
    -- an alpha into each child's colour fields (see :fadeAlpha below); aliasing the
    -- shared theme table here meant such a mod mutated UI.color.border for every widget
    -- in the mod at once. It happened to be survivable only because UI.roundRect takes
    -- alpha as a separate argument and ignores c.a -- not something to rely on.
    local b = UI.color.border
    o.borderColor = { r = b.r, g = b.g, b = b.b, a = b.a }
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

-- How visible this button should currently be, 0..1.
--
-- Sidebar mods (Minimal Sidebar and friends) fade the vanilla icon column by writing an
-- alpha into every child's standard colour fields and letting each child's own render
-- multiply by it -- which ISButton does, and which this button did NOT, because it
-- paints entirely with its own hardcoded alphas. That is why it stayed at full opacity
-- while every neighbour faded out. Reading the fields back here restores the contract
-- generically: no mod is named or detected, anything using the standard mechanism works.
--
-- backgroundColor is deliberately excluded -- we set it fully transparent above, so
-- folding it in would report "faded" permanently.
function HudIcon:fadeAlpha()
    local a = 1
    local t = self.textureColor          -- created by ISButton:new at a=1
    if type(t) == "table" and t.a then a = math.min(a, t.a) end
    local b = self.borderColor
    if type(b) == "table" and b.a then a = math.min(a, b.a) end
    if a < 0 then return 0 end
    if a > 1 then return 1 end
    return a
end

-- Suppressed: ISButton's own prerender paints a background and border we don't want.
-- The drawing lives in :render() below -- see the note there, it matters for fading.
function HudIcon:prerender() end

-- Drawn in RENDER, not prerender, unlike every other widget in this file.
--
-- Sidebar mods fade their children by wrapping the child's *prerender* and writing the
-- alpha into its colour fields AFTER calling the original:
--     child.prerender = function(c) originalPrerender(c); applyColours(c, fadeAlpha) end
-- PZ then calls render(). So a widget that paints in prerender reads the alpha set on
-- the PREVIOUS frame, while one that paints in render reads the value set moments
-- earlier in the current one. Vanilla ISButton paints in render, which is why an
-- ordinary sidebar button (and Aegis Panel's, which is a plain ISButton + setImage)
-- fades perfectly without doing anything special. Matching that ordering here means
-- this button tracks the fade exactly rather than trailing it by a frame.
function HudIcon:render()
    local fade = self:fadeAlpha()
    if fade <= 0.01 then return end      -- faded out by a sidebar mod: draw nothing
    local w, h = self:getWidth(), self:getHeight()
    local c = UI.color
    local player = getPlayer()
    local name, faction = nil, nil
    if player then name, faction = FF.getFactionOfPlayer(player:getUsername()) end
    local underRaid = faction ~= nil and faction.raid ~= nil
    local col = name and UI.factionColor(name) or c.accent

    local ring = underRaid and c.bad or (self:isMouseOver() and col or c.border)
    local inset = underRaid and 2 or 1
    -- Scale the frame with the button so it reads the same at 34px in the corner
    -- and at 48-128px in the sidebar.
    local short = math.min(w, h)
    local radius = math.max(4, math.floor(short * 0.26))
    -- Every alpha below is scaled by `fade` so the whole button dims as one.
    UI.roundRect(self, 0, 0, w, h, radius, 1.0 * fade, ring)
    UI.roundRect(self, inset, inset, w - 2 * inset, h - 2 * inset,
        math.max(1, radius - inset), 0.85 * fade, c.titlebar)
    -- The branded emblem is square, so fit it to the SHORT edge and centre it --
    -- sidebar buttons are 4:3. It is already coloured; drawing with white preserves
    -- the supplied purple artwork instead of tinting it with the faction colour.
    local pad = math.max(2, math.floor(short * 0.10))
    local size = short - 2 * pad
    if not UI.drawIcon(self, "ic_brand", math.floor((w - size) / 2),
            math.floor((h - size) / 2), size, c.white, fade) then
        self:drawTextCentre("F", math.floor(w / 2), math.floor((h - UI.fh(UI.font.title)) / 2),
            col.r, col.g, col.b, 1.0 * fade, UI.font.title)
    end
end

-- Danger dimming (see UI.installDimming's own comment in LFS_UI.lua for the
-- full mechanism): every widget class the tabs above are built from needs the
-- override installed once so its instances' draw calls respect UI.dimAlpha,
-- whichever `el` (panel or child) they end up called against.
UI.installDimming(StatRow)
UI.installDimming(Notice)
UI.installDimming(CreationRequirement)
UI.installDimming(ClaimAreaList)
UI.installDimming(RolePermRow)
UI.installDimming(ColorSwatch)

-- ===========================================================================
-- LasciviousFactionsSystemPanel : a custom ISPanel window
-- ===========================================================================
-- Rebuilt from the old ISCollapsableWindow to match the Aegis look: a branded
-- header, a full-height animated sidebar nav with a gliding accent indicator,
-- and a rounded/shadowed body. `self.content` keeps the same local (0,0) origin
-- as before, so every populateX section builder and the embedded claim map are
-- unaffected by the chrome swap.
LasciviousFactionsSystemPanel = ISPanel:derive("LasciviousFactionsSystemPanel")

local HEADER_H = 46
-- Always-visible status strip between the header and the body (raid / war /
-- upkeep / territory chips). Sits above BOTH the sidebar and the content area,
-- so everything below the header starts at BODY_TOP.
local STATUS_H = 32
local BODY_TOP = HEADER_H + STATUS_H
local NAV_TOP = BODY_TOP + 12
local NAV_ITEM_H = 34
local NAV_GAP = 4
local WINDOW_RADIUS = 14

-- Resize / collapse limits. MIN_WINDOW_HEIGHT is sized so the full nav list still
-- fits at full row pitch, so the window can never be dragged small enough to clip a
-- tab (the prerender nav-fit is a further safety net above this).
local MIN_WINDOW_WIDTH  = 620
-- Three group captions ride above the nav rows now. Budgeted at a flat 28px each
-- rather than through UI.fh: this is a load-time constant and the font atlas is not
-- queryable yet here. 28 covers the largest atlas's caption row, so the floor is
-- generous rather than tight -- the prerender nav-fit absorbs any slack.
local NAV_CAPTION_BUDGET = 3 * 28
local MIN_WINDOW_HEIGHT = NAV_TOP + #SECTIONS * (NAV_ITEM_H + NAV_GAP)
    + NAV_CAPTION_BUDGET + WINDOW_RADIUS + 8
local RESIZE_GRIP       = 14   -- corner drag-handle hit size
local COLLAPSED_H       = HEADER_H + 2

-- Invisible corner drag-handle. It lives as a child of the panel, added AFTER the
-- content pane so it sits on top and wins the hit-test even over the content area.
-- It forwards the engine's clean incremental mouse deltas to the panel, which does
-- the clamping + reflow -- side-stepping ISResizeWidget's anchor/absolute-delta math
-- (which doesn't fit a bottom-left handle on a manually-positioned window).
local ResizeGrip = ISPanel:derive("FFResizeGrip")
function ResizeGrip:new(x, y, size, corner, panel)
    local o = ISPanel:new(x, y, size, size)
    setmetatable(o, self); self.__index = self
    o.background = false
    o.corner = corner   -- "bl" | "br"
    o.panel = panel
    o.dragging = false
    return o
end
function ResizeGrip:onMouseDown(x, y)
    self.dragging = true
    self:setCapture(true)
    if self.panel then self.panel:bringToTop() end
    return true
end
function ResizeGrip:onMouseMove(dx, dy)
    if self.dragging and self.panel then self.panel:resizeByDelta(self.corner, dx, dy) end
end
function ResizeGrip:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end
function ResizeGrip:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        self:setCapture(false)
        if self.panel then self.panel:endResize() end
    end
    return true
end
function ResizeGrip:onMouseUpOutside(x, y) return self:onMouseUp(x, y) end
function ResizeGrip:prerender() end
function ResizeGrip:render() end

-- Mirrors the raidprogress push LFS_Client.lua already listens to
-- (same event, same command, both listeners fire independently) so the panel
-- can show a live bar instead of only a halo note.
LasciviousFactionsSystemPanel.raidProgress = {}

local function receivePanelRaidProgress(module, command, args)
    if module ~= FF.MODULE or command ~= "raidprogress" then return end
    if type(args) ~= "table" or type(args.defender) ~= "string" then return end
    LasciviousFactionsSystemPanel.raidProgress[args.defender] = args
end
if FF._panelRaidProgressHook then Events.OnServerCommand.Remove(FF._panelRaidProgressHook) end
FF._panelRaidProgressHook = receivePanelRaidProgress
Events.OnServerCommand.Add(receivePanelRaidProgress)

-- Live refresh: whenever the replicated registry updates (our mutation or one
-- from another player/officer), redraw the open section instead of leaving stale
-- data on screen. LFS_Client.lua documents that the local ModData
-- store is already updated by the engine before any Lua handler fires, so
-- FF.getData() is fresh here regardless of file load order.
local function receivePanelGlobalData(tableName, tableData)
    if tableName ~= FF.MODDATA then return end
    local inst = LasciviousFactionsSystemPanel.instance
    if inst then inst:requestRebuild() end
end
if FF._panelGlobalDataHook then Events.OnReceiveGlobalModData.Remove(FF._panelGlobalDataHook) end
FF._panelGlobalDataHook = receivePanelGlobalData
Events.OnReceiveGlobalModData.Add(receivePanelGlobalData)

-- Rebuilding the open tab means clearChildren() plus the whole builder again -- sorts,
-- string.formats and dozens of fresh widgets -- and it used to run on EVERY sync,
-- whether or not the tab showed anything that changed. The server syncs on a timer
-- (score-credit flush, decay, pact, season) as well as on every mutation, so
-- an idle panel was being torn down and rebuilt several times a minute.
--
-- Leading-edge throttle, deliberately not a plain interval: the FIRST sync after a
-- quiet period rebuilds immediately, so clicking Deposit still updates the balance the
-- instant the server answers. Only a burst arriving inside the window is collapsed
-- into one rebuild at the end of it.
local REBUILD_INTERVAL = 1

function LasciviousFactionsSystemPanel:rebuildNow()
    self.pendingRebuild = false
    self.lastRebuildAt = getTimestamp and getTimestamp() or nil
    if not self.activeSection then return end
    -- Guarded: a stale instance (see toggle) must not throw on every sync.
    pcall(function() self:showSection(self.activeSection) end)
end

function LasciviousFactionsSystemPanel:requestRebuild()
    -- Nothing visible to refresh while minimized; restoring rebuilds the section anyway.
    if self.collapsed or not self.activeSection then return end
    local now = getTimestamp and getTimestamp() or nil
    if (not now) or (not self.lastRebuildAt) or (now - self.lastRebuildAt) >= REBUILD_INTERVAL then
        self:rebuildNow()
    else
        self.pendingRebuild = true
    end
end

function LasciviousFactionsSystemPanel:initialise()
    ISPanel.initialise(self)
end

-- The player's own faction name (drives the header label and the accent colour).
function LasciviousFactionsSystemPanel:playerFactionName()
    local p = getPlayer()
    if not p then return nil end
    return (FF.getFactionOfPlayer(p:getUsername()))
end

-- The local player's username, or nil before the player exists. Guarded because
-- :prerender() can run during a load screen, where getPlayer() is still nil.
function LasciviousFactionsSystemPanel:localUsername()
    local p = getPlayer()
    return p and p:getUsername() or nil
end

-- Drops "debug" unless FF.getOptions().debugToolsEnabled is true (true
-- singleplayer + the Debug sandbox flag, see LFS_Shared.lua) -- so the section
-- is not just disabled but literally absent from the sidebar/nav otherwise.
-- Called at most once a second (see CHROME_TTL/cachedNavRows below), so
-- rebuilding a small filtered array here is not worth memoizing further.
function LasciviousFactionsSystemPanel:visibleSections()
    if FF.getOptions().debugToolsEnabled then
        return SECTIONS
    end
    local visible = {}
    for _, s in ipairs(SECTIONS) do
        if s.key ~= "debug" then visible[#visible + 1] = s end
    end
    return visible
end

-- The sidebar as it is actually drawn: the visible sections with a caption row
-- inserted ahead of each group. Returns the scrolling body list and the pinned footer
-- list separately, because the footer is laid out from the bottom up.
--
-- A caption is only emitted once its group has a surviving row.
function LasciviousFactionsSystemPanel:navRows()
    local body, footer = {}, {}
    local lastGroup
    for _, s in ipairs(self:visibleSections()) do
        if s.group == "footer" then
            footer[#footer + 1] = { section = s }
        else
            if s.group ~= lastGroup then
                body[#body + 1] = { caption = s.group }
                lastGroup = s.group
            end
            body[#body + 1] = { section = s }
        end
    end
    return body, footer
end

-- The panel chrome is redrawn every frame, but the DATA behind it changes at human
-- speed. These two memos keep the redraw while dropping the recompute:
--
--   * navRows walks the section list and allocates a row table per entry.
--   * statusChips scans every faction looking for an outgoing raid, scans every war,
--     and makes three separate FF.getData() calls -- the most expensive thing in
--     prerender by a distance.
--
-- One second, so the upkeep countdown (minute-granular) and the war score still tick
-- on their own without needing a section rebuild -- which is what the note in
-- :prerender is about.
local CHROME_TTL = 1

local function chromeExpired(at)
    local now = getTimestamp and getTimestamp() or nil
    if not now then return true, nil end
    if not at or (now - at) >= CHROME_TTL then return true, now end
    return false, now
end

function LasciviousFactionsSystemPanel:cachedNavRows()
    local expired, now = chromeExpired(self.navRowsAt)
    if expired or not self.navRowsCache then
        local body, footer = self:navRows()
        self.navRowsCache = { body, footer }
        self.navRowsAt = now
    end
    return self.navRowsCache[1], self.navRowsCache[2]
end

function LasciviousFactionsSystemPanel:cachedStatusChips()
    local expired, now = chromeExpired(self.chipsAt)
    if expired or not self.chipsCache then
        self.chipsCache = self:statusChips()
        self.chipsAt = now
    end
    return self.chipsCache
end

-- ---------------------------------------------------------------------------
-- Header action slot
-- ---------------------------------------------------------------------------
-- One button per tab, living in the window header beside the bell. The design this
-- panel follows gives each tab a single "the thing you came here to do" control and
-- puts it where it is always in the same place -- Overview offers "Manage claim",
-- Claims offers "Make a shop claim", Members offers "+ Invite". Putting it in the
-- header instead of at the bottom of the tab means it does not move as content grows,
-- and does not scroll away.
--
-- A builder claims the slot by calling :setHeaderAction() while it runs; showSection
-- clears the slot first, so a tab that wants nothing there simply says nothing.
--
-- Search fields deliberately do NOT come here even though the source mockup puts the
-- member search in the header: the header already carries the bell, minimize and
-- close, and a text entry wedged among them is a fiddly target. Searches stay in the
-- content area beside the thing they filter instead.
function LasciviousFactionsSystemPanel:setHeaderAction(label, onclick, variant, iconName)
    self.headerActionSpec = label and
        { label = label, onclick = onclick, variant = variant or "primary", icon = iconName } or nil
end

-- Rebuild the header button to match the current spec. Called after every section
-- build; cheap, and only touches the widget tree when the spec actually changed.
function LasciviousFactionsSystemPanel:syncHeaderAction()
    local spec = self.headerActionSpec
    local key = spec and (spec.label .. "\0" .. tostring(spec.variant)) or nil
    if key == self.headerActionKey then return end
    self.headerActionKey = key
    if self.headerActionBtn then
        self:removeChild(self.headerActionBtn)
        self.headerActionBtn = nil
    end
    if not spec then
        self.headerActionX = nil
        return
    end
    -- Clamped to the header band for the same reason the emblem is (HEADER_H is a
    -- literal, the font is not).
    local h = math.min(UI.rowH(UI.font.small), HEADER_H - 12)
    local btn = FFButton:new(0, 0, UI.buttonWidth(spec.label, spec.icon ~= nil, h, UI.font.small),
        h, spec.label, self, spec.onclick, spec.variant, spec.icon)
    btn.font = UI.font.small
    btn:initialise()
    self:addChild(btn)
    self.headerActionBtn = btn
end

-- Position the header button each frame: right-aligned just left of the bell, so it
-- tracks a resize. Records headerActionX so the identity block above knows where to
-- stop clipping the faction name.
function LasciviousFactionsSystemPanel:layoutHeaderAction(w)
    local btn = self.headerActionBtn
    if not btn then self.headerActionX = nil return end
    if self.collapsed then
        btn:setVisible(false)
        self.headerActionX = nil
        return
    end
    btn:setVisible(true)
    local x = w - 88 - btn:getWidth()
    btn:setX(x)
    btn:setY(math.floor((HEADER_H - btn:getHeight()) / 2))
    self.headerActionX = x
end

-- Caption rows are shorter than nav rows: they carry one line of small text and no
-- hit target, so they should not eat a full row's worth of sidebar.
local function navCaptionH() return UI.fh(UI.font.small) + 10 end

-- Sub-tabs of the Factions section. Leaderboard drops out when the server has
-- the leaderboard disabled -- the same gate the sidebar row used to carry.
function LasciviousFactionsSystemPanel:visibleFactionSubTabs()
    local out = {}
    local lbOn = FF.getOptions().leaderboardEnabled
    for _, t in ipairs(FACTION_SUBTABS) do
        if t.key ~= "leaderboard" or lbOn then out[#out + 1] = t end
    end
    return out
end

-- The raid currently being pressed against the player's own faction, with live
-- headcounts, or nil. Only INCOMING raids qualify: raiding someone else is a thing you
-- chose to do and stays a chip, being raided is a thing happening to you.
function LasciviousFactionsSystemPanel:activeRaid()
    local player = getPlayer()
    if not player then return nil end
    local name, faction = FF.getFactionOfPlayer(player:getUsername())
    if not (faction and faction.raid) then return nil end
    local progress = LasciviousFactionsSystemPanel.raidProgress[name]
    return {
        attacker = tostring(faction.raid.attacker),
        attackers = (progress and progress.attackers) or 0,
        defenders = (progress and progress.defenders) or 0,
    }
end

-- The chips in the always-visible status strip: raid, war, territory.
-- Read-only and cheap (no allocation beyond the returned list) -- :prerender
-- calls this every frame so the countdowns tick live.
function LasciviousFactionsSystemPanel:statusChips()
    local c = UI.color
    local player = getPlayer()
    if not player then return {} end
    local name, faction = FF.getFactionOfPlayer(player:getUsername())
    if not faction then
        return { { text = FF.tr("Not in a faction"), color = c.faint } }
    end
    local opts = FF.getOptions()
    local chips = {}

    -- Raid: only the outgoing case. Being raided takes over the whole strip as a band
    -- (see :activeRaid), and :prerender never reaches the chips while that is showing.
    local target
    for otherName, other in pairs(FF.getData().factions or {}) do
        if other.raid and other.raid.attacker == name then target = otherName break end
    end
    chips[#chips + 1] = target
        and { text = FF.text("UI_LFS_StatusRaiding", "Raiding %s", target), color = c.warn }
        or  { text = FF.tr("No active raid"), color = c.faint }

    -- War: one chip per war, principal-vs-principal score.
    if opts.warsEnabled then
        for _, war in pairs(FF.getData().wars or {}) do
            local side = (war.a == name and "a") or (war.b == name and "b")
                or (war.coalition and war.coalition[name])
            if side then
                local mine = (side == "a") and war.a or war.b
                local theirs = (side == "a") and war.b or war.a
                chips[#chips + 1] = { color = c.bad,
                    text = FF.text("UI_LFS_StatusAtWar", "At war - %s %d-%d",
                        theirs, (war.score and war.score[mine]) or 0,
                        (war.score and war.score[theirs]) or 0) }
            end
        end
    end

    local claimed = FF.totalArea(faction.claims)
    local maxTiles = FF.maxClaimTiles(FF.factionScore(faction, opts), opts)
    local frac = (maxTiles > 0) and (claimed / maxTiles) or 0
    chips[#chips + 1] = { text = FF.text("UI_LFS_StatusTerritoryUsed",
        "Territory %d%% used", math.floor(frac * 100 + 0.5)),
        color = frac >= 0.9 and c.warn or c.faint }
    return chips
end

-- Fully custom chrome: soft shadow, rounded body, branded header, and a
-- self-drawn sidebar nav (hover glide + gliding accent indicator).
-- Danger dimming + attack auto-close: same reasoning and cadence as
-- LasciviousShop_Window.lua's own updateDangerAlpha/checkAttackedClose -- a
-- zombie closing in (or an actual hit landing) while a player is heads-down
-- in faction menus is exactly the "got ambushed while distracted" scenario
-- that system exists to prevent, and this panel can stay open just as long.
local DANGER_CHECK_INTERVAL_MS = 400
local DANGER_RADIUS_TILES = 4
local DANGER_DIM_ALPHA = 0.25

-- The only writer of UI.dimAlpha (once per frame, right here) -- every FF*
-- widget class only reads it via UI.installDimming, see that comment in
-- LFS_UI.lua for why this alone is enough to dim the whole panel tree.
function LasciviousFactionsSystemPanel:updateDangerAlpha()
    local now = getTimestampMs and getTimestampMs() or 0
    if not self._dangerCheckedAtMs or now - self._dangerCheckedAtMs >= DANGER_CHECK_INTERVAL_MS then
        self._dangerCheckedAtMs = now
        local ok, player = pcall(getPlayer)
        self._dangerNear = ok and player
            and LasciviousFactionsDanger.zombiesNear(player, DANGER_RADIUS_TILES)
            or false
    end
    local target = self._dangerNear and DANGER_DIM_ALPHA or 1.0
    UI.dimAlpha = UI.glide(UI.dimAlpha or 1.0, target, 0.25)
end

-- Force-closes the panel the moment the player takes a hit from an actual
-- attacker (zombie, animal, or another player) -- the hard backstop for when
-- the dimming above isn't enough. getAttackedBy() only ever gets set by
-- combat, never by hunger/thirst/cold/disease/fall damage, so "normal"
-- damage naturally never triggers this -- no extra filtering needed. Baseline
-- is whatever getAttackedBy() already returned when the panel was opened
-- (see .toggle()), so a fight that was already winding down before the
-- player opened the panel doesn't instantly slam it shut; only a genuinely
-- NEW hit does.
function LasciviousFactionsSystemPanel:checkAttackedClose()
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

function LasciviousFactionsSystemPanel:prerender()
    self:updateDangerAlpha()
    self:checkAttackedClose()
    -- See liveRefreshFingerprint's own comment: cheap once-per-second check for the
    -- active tab's underlying data changing (faction just created/joined, a
    -- permission toggled, a deposit/withdraw/passive tax landed) so the tab
    -- rebuilds itself instead of sitting stale until the player navigates away
    -- and back. Runs before anything else here so an early return further down
    -- (the active-raid takeover, below) can never skip it.
    local fingerprintNow = getTimestamp()
    if fingerprintNow ~= self._liveFingerprintCheckedAt then
        self._liveFingerprintCheckedAt = fingerprintNow
        local ok, fp = pcall(LasciviousFactionsSystemPanel.liveRefreshFingerprint, self)
        if ok and fp ~= nil and fp ~= self._liveRefreshFingerprint then
            self:showSection(self.activeSection)
        end
    end

    -- "vehicles" splits its live-update into two DIFFERENT problems, not one:
    --
    -- 1) Real data changing (a protect/confirm/lock/unlock actually landing)
    --    -- this is the SAME kind of event tribute's own fingerprint above
    --    already handles correctly (a deposit/withdraw landing), so it uses
    --    the exact same mechanism: "vehicles" is back in LIVE_REFRESH_SECTIONS
    --    with its own plain fingerprint branch (registry contents, no time
    --    component at all -- matching tribute's own shape exactly). This
    --    only rebuilds -- 3D scenes included -- when something ACTUALLY
    --    changed, never on a bare timer.
    -- 2) The pending-protection countdown ticking even when NOTHING changed
    --    -- a fingerprint can't and shouldn't try to detect "time passed
    --    with no data change", so this is handled completely separately
    --    below: mutate the already-existing status labels' text in place
    --    (ISLabel:setName(), the same in-place-update idiom
    --    FactionAreaAccessDialog:syncControls() already uses elsewhere in
    --    this file) every frame, with NO section rebuild and NO 3D scene
    --    recreation at all -- this is what makes it cheap enough to run
    --    unthrottled.
    if self.activeSection == "vehicles" and self.vehiclePendingLabels then
        local username = getPlayer() and getPlayer():getUsername()
        local _, faction = username and FF.getFactionOfPlayer(username)
        if faction and faction.vehicles then
            local nowHours = getGameTime():getWorldAgeHours()
            for id, label in pairs(self.vehiclePendingLabels) do
                local entry = faction.vehicles.protected[id]
                if entry and not entry.protectedAt then
                    local remaining = math.max(0, FF.VEHICLE_PROTECT_CONFIRM_HOURS
                        - (nowHours - (entry.requestedAt or nowHours)))
                    local mins = math.max(1, math.ceil(remaining * 60))
                    pcall(function()
                        label:setName(FF.text("UI_LFS_VehicleStatusPending",
                            "Proteção pendente -- confirma em %s min de jogo", tostring(mins)))
                    end)
                end
            end
        end
    end

    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()

    -- Entrance slide-in (framerate-independent). Suspended while dragging.
    self.anim = UI.glide(self.anim or 0, 1, 0.2)
    if not (self.dragging or self._resizing) then
        self:setY(self.baseY + (1 - self.anim) * 16)
    end

    UI.shadow(self, 0, 0, w, h, 30, 0.5)
    UI.roundFrame(self, 0, 0, w, h, WINDOW_RADIUS, 1.0, c.border, c.bg)

    -- Header band: rounded top corners, squared where it meets the body, with a
    -- faint accent sheen from the top and the accent underline beneath it.
    UI.roundRect(self, 1, 1, w - 2, HEADER_H, WINDOW_RADIUS, 1.0, c.titlebar)
    self:drawRect(1, HEADER_H - WINDOW_RADIUS, w - 2, WINDOW_RADIUS, 1.0, c.titlebar.r, c.titlebar.g, c.titlebar.b)
    local grad = UI.icon("ui_grad")
    if grad then self:drawTextureScaled(grad, 1, 1, w - 2, HEADER_H - 3, 0.06, c.accent.r, c.accent.g, c.accent.b) end
    self:drawRect(1, HEADER_H - 2, w - 2, 2, 1.0, c.accent.r, c.accent.g, c.accent.b)

    -- Before the identity block, which clips the faction name against headerActionX.
    self:layoutHeaderAction(w)

    -- HEADER_H is a literal 46 while the fonts scale with the player's Font Size, and
    -- at the largest atlas fh(title) alone is 53 -- taller than the band it draws in.
    -- Step down a font rather than clip: the wordmark this replaced had the same
    -- problem and simply overflowed. (THE RULE in the toolkit says a text-bearing
    -- height must derive from fh(); the header predates it, so the text adapts to the
    -- fixed band instead.)
    local headFont = (UI.fh(UI.font.title) <= HEADER_H - 8) and UI.font.title or UI.font.body

    -- Identity: emblem, faction name, role. This used to be a generic "FACTIONS"
    -- wordmark with the faction name shrunk into the far corner, and every tab then
    -- repeated the identity underneath as a tall hero block -- so the panel spent its
    -- most valuable strip saying what app you were in, and spent it again on each tab.
    -- The identity now lives here once, and the tabs start straight into content.
    local fname = self:playerFactionName()
    local hx = 14
    if fname then
        local faction = FF.getFaction(fname)
        -- Derived from the title font so it scales with the atlas, but clamped to the
        -- header: HEADER_H is a literal 46, and at the largest Font Size setting
        -- fh(title) alone is already close to that, so an unclamped emblem would
        -- overflow the band it sits in.
        local em = math.min(UI.fh(headFont) + 6, HEADER_H - 10)
        local ec = UI.factionColor(fname)
        local ey = math.floor((HEADER_H - em) / 2)
        UI.roundFrame(self, hx, ey, em, em, 6, 1.0,
            { r = ec.r * 0.85, g = ec.g * 0.85, b = ec.b * 0.85 }, ec)
        local on = UI.readableOn(ec)
        self:drawTextCentre(UI.initials(fname), hx + math.floor(em / 2),
            ey + math.floor((em - UI.fh(UI.font.small)) / 2), on.r, on.g, on.b, 1.0, UI.font.small)
        hx = hx + em + 10

        -- Name, then the role pill. Both are clipped to whatever is left before the
        -- action slot the tab may have claimed (headerActionX, set below).
        local rightEdge = (self.headerActionX or (w - 86)) - 10
        local nameW = UI.tw(headFont, fname)
        self:drawText(UI.fit(headFont, fname, math.max(0, rightEdge - hx)), hx,
            math.floor((HEADER_H - UI.fh(headFont)) / 2),
            c.text.r, c.text.g, c.text.b, 1.0, headFont)
        hx = hx + nameW + 10

        local role = (faction and faction.members and faction.members[self:localUsername()]) or nil
        local roleText = role and FF.tr(role) or nil
        if roleText and hx + UI.tw(UI.font.small, roleText) + 20 < rightEdge then
            local rc = (role == "owner") and c.accent or ((role == "officer") and c.warn or c.dim)
            local ph = UI.badgeH()
            local pw = UI.tw(UI.font.small, roleText) + 16
            local py = math.floor((HEADER_H - ph) / 2)
            UI.roundRect(self, hx, py, pw, ph, math.floor(ph / 2), 0.20, rc)
            self:drawText(roleText, hx + 8, py + math.floor((ph - UI.fh(UI.font.small)) / 2),
                rc.r, rc.g, rc.b, 1.0, UI.font.small)
        end
    else
        -- Factionless: no identity to show, so the wordmark still earns its place.
        local chipY = math.floor((HEADER_H - 18) / 2)
        UI.roundFrame(self, hx, chipY, 18, 18, 5, 1.0, c.accent,
            { r = c.accent.r * 0.5, g = c.accent.g * 0.5, b = c.accent.b * 0.5 })
        self:drawText(FF.tr("FACTIONS"), hx + 26, math.floor((HEADER_H - UI.fh(headFont)) / 2),
            c.text.r, c.text.g, c.text.b, 1.0, headFont)
    end

    -- Notification bell, left of the window affordances. Faction events used to exist
    -- only as chat lines, so anything that happened while the player was looting was
    -- simply gone; this is the way back to them. Hidden while collapsed: the dropdown
    -- would hang below the header band, outside the panel's own bounds.
    if self.collapsed then
        self.bellRect, self.notifOpen = nil, false
        self:syncNotifPanel()
    else
        local blX, blY = w - 72, math.floor((HEADER_H - 16) / 2)
        self.bellRect = { x = blX, y = blY, w = 16, h = 16 }
        local overBell = self:isMouseOver()
            and self:getMouseX() >= blX and self:getMouseX() <= blX + 16
            and self:getMouseY() >= blY and self:getMouseY() <= blY + 16
        local bellCol = (self.notifOpen or overBell) and c.text or c.dim
        -- ic_bell, not ic_star. The star shipped here as a stand-in when the icon set had
        -- no bell, and it read as a favourite rather than a notification -- worse, ic_star
        -- already means "officer" on the member roster, so one glyph was
        -- carrying two unrelated meanings. The fallback stays for the case where the
        -- texture fails to load: a filled dot still reads as "there is something here"
        -- and never leaves a blank gap in the header.
        if not UI.drawIcon(self, "ic_bell", blX, blY, 16, bellCol) then
            UI.roundRect(self, blX + 3, blY + 3, 10, 10, 5, 1.0, bellCol)
        end
        if (FF.eventLogUnread or 0) > 0 then
            UI.roundRect(self, blX + 10, blY - 1, 7, 7, 4, 1.0, c.bad)
        end
        -- Re-laid out every frame so a resize or a fresh event resizes it under the
        -- player rather than at the next open.
        self:syncNotifPanel()
    end

    -- Close affordance (top-right). Must stay fully legible (and, while a
    -- zombie is close, stand out even MORE than usual) no matter how faded
    -- the rest of the panel gets -- see updateDangerAlpha/UI.installDimming's
    -- own comment. ffNoDim only brackets the drawing itself; input handling
    -- for this rect is already unconditional regardless of dimming.
    local clX, clY = w - 28, math.floor((HEADER_H - 16) / 2)
    self.closeRect = { x = clX, y = clY, w = 16, h = 16 }
    local overClose = self:isMouseOver()
        and self:getMouseX() >= clX and self:getMouseX() <= clX + 16
        and self:getMouseY() >= clY and self:getMouseY() <= clY + 16
    local xc = self._dangerNear and c.bad or (overClose and c.text or c.dim)
    self.ffNoDim = true
    self:drawText("X", clX + 4, clY, xc.r, xc.g, xc.b, 1.0, UI.font.body)
    self.ffNoDim = false

    -- Minimize / restore affordance, just left of the close X.
    local mnX, mnY = w - 48, clY
    self.minRect = { x = mnX, y = mnY, w = 16, h = 16 }
    local overMin = self:isMouseOver()
        and self:getMouseX() >= mnX and self:getMouseX() <= mnX + 16
        and self:getMouseY() >= mnY and self:getMouseY() <= mnY + 16
    local mnc = overMin and c.text or c.dim
    if self.collapsed then
        self:drawRectBorder(mnX + 3, mnY + 3, 10, 10, 1.0, mnc.r, mnc.g, mnc.b)   -- restore: hollow square
    else
        self:drawRect(mnX + 3, mnY + 11, 10, 2, 1.0, mnc.r, mnc.g, mnc.b)         -- minimize: bottom bar
    end

    -- Collapsed to the header bar: skip the status strip, sidebar, nav and grips.
    if self.collapsed then return end

    -- Being raided takes the whole status strip: a chip in a row of chips is exactly
    -- the wrong weight for the one event the player has to act on immediately. The
    -- strip is already full-width and always present, so this needs no reflow -- the
    -- chips simply do not draw while it is showing.
    local raid = self:activeRaid()
    if raid then
        local bad = c.bad
        self:drawRect(1, HEADER_H, w - 2, STATUS_H, 0.16, bad.r, bad.g, bad.b)
        self:drawRect(1, HEADER_H, w - 2, 2, 1.0, bad.r, bad.g, bad.b)
        local isz = 16
        UI.drawIcon(self, "ic_flame", 18, HEADER_H + math.floor((STATUS_H - isz) / 2), isz, bad)
        local text = FF.text("UI_LFS_RaidIncomingStatus",
            "Under attack by %s - %d attackers vs %d defenders inside your claim",
            raid.attacker, raid.attackers, raid.defenders)
        self:drawText(UI.fit(UI.font.body, text, w - 60),
            42, HEADER_H + math.floor((STATUS_H - UI.fh(UI.font.body)) / 2),
            c.text.r, c.text.g, c.text.b, 1.0, UI.font.body)
        return self:drawNavAndGrips(w, h)
    end

    -- Status strip: the four at-a-glance chips, recomputed every frame so the
    -- upkeep countdown and war score tick without a section rebuild. Chips that
    -- would run past the window edge are simply dropped.
    local sx = 20
    for _, chip in ipairs(self:cachedStatusChips()) do
        local cw = UI.chipWidth(chip.text)
        if sx + cw > w - 16 then break end
        UI.chip(self, sx, HEADER_H + 6, 20, chip.text, chip.color)
        sx = sx + cw + 8
    end

    return self:drawNavAndGrips(w, h)
end

-- "just now" / "6m ago" / "3h ago" / "2d ago". Minute-granular, unlike
-- Event history is read to work out how stale a thing is, and
-- "just now" for everything inside an hour would flatten exactly that.
local function agoText(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return FF.text("UI_LFS_AgoNow", "just now") end
    if seconds < 3600 then
        return FF.text("UI_LFS_AgoMinutes", "%dm ago", math.floor(seconds / 60))
    end
    if seconds < 86400 then
        return FF.text("UI_LFS_AgoHours", "%dh ago", math.floor(seconds / 3600))
    end
    return FF.text("UI_LFS_AgoDays", "%dd ago", math.floor(seconds / 86400))
end

-- NotifDropdown: the bell's panel of recent faction events. A real child rather than
-- something painted in :render, because it hangs over the content pane and has to win
-- the hit-test there -- the same reason the resize grips are added after `content`.
-- Read-only: it swallows its clicks so they cannot fall through to the tab underneath.
local NOTIF_MAX_ROWS = 6

local NotifDropdown = ISPanel:derive("FFNotifDropdown")

function NotifDropdown.rowHeight() return UI.lineH(UI.font.body) + UI.lineH(UI.font.small) + 8 end

function NotifDropdown:new()
    local o = ISPanel:new(0, 0, 320, 100)
    setmetatable(o, self); self.__index = self
    o.background = false
    return o
end

-- Sized to the log it is about to show, then pinned under the bell.
function NotifDropdown:layoutIn(panel)
    local rows = math.max(1, math.min(#(FF.eventLog or {}), NOTIF_MAX_ROWS))
    local w = math.min(320, panel:getWidth() - 24)
    self:setWidth(w)
    self:setHeight(UI.lineH(UI.font.small) + 8 + rows * NotifDropdown.rowHeight() + 6)
    self:setX(panel:getWidth() - w - 12)
    self:setY(HEADER_H + 4)
end

function NotifDropdown:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    UI.shadow(self, 0, 0, w, h, 16, 0.45)
    UI.roundFrame(self, 0, 0, w, h, 10, 1.0, c.border, c.card)

    local ty = 6
    self:drawText(FF.tr("RECENT EVENTS"), 12, ty, c.faint.r, c.faint.g, c.faint.b, 1.0, UI.font.small)
    ty = ty + UI.lineH(UI.font.small) + 4

    local log = FF.eventLog or {}
    if #log == 0 then
        self:drawText(FF.tr("Nothing has happened yet."), 12, ty,
            c.dim.r, c.dim.g, c.dim.b, 1.0, UI.font.body)
        return
    end
    local now = getTimestamp()
    local rowH = NotifDropdown.rowHeight()
    for i = 1, math.min(#log, NOTIF_MAX_ROWS) do
        local e = log[i]
        self:drawText(UI.fit(UI.font.body, e.text, w - 24), 12, ty,
            c.text.r, c.text.g, c.text.b, 1.0, UI.font.body)
        self:drawText(agoText(now - (e.at or now)), 12, ty + UI.lineH(UI.font.body),
            c.faint.r, c.faint.g, c.faint.b, 1.0, UI.font.small)
        ty = ty + rowH
    end
end

function NotifDropdown:onMouseDown() return true end
function NotifDropdown:onMouseUp() return true end

UI.installDimming(NotifDropdown)

-- Push self.notifOpen onto the child. Called wherever the flag changes, and from
-- :prerender, so the panel resizes under an open dropdown without stale geometry.
function LasciviousFactionsSystemPanel:syncNotifPanel()
    if not self.notifPanel then return end
    local show = self.notifOpen and not self.collapsed or false
    if show then self.notifPanel:layoutIn(self) end
    self.notifPanel:setVisible(show)
end

-- Everything below the status strip. Split out of :prerender only so the raid band
-- can hand off to it without duplicating the sidebar.
function LasciviousFactionsSystemPanel:drawNavAndGrips(w, h)
    local c = UI.color

    -- Sidebar band (rounded bottom-left to match the window).
    self:drawRect(1, BODY_TOP + 1, SIDEBAR_WIDTH, h - BODY_TOP - WINDOW_RADIUS, 1.0, c.panel.r, c.panel.g, c.panel.b)
    UI.roundRect(self, 1, h - WINDOW_RADIUS - 1, SIDEBAR_WIDTH, WINDOW_RADIUS, WINDOW_RADIUS - 1, 1.0, c.panel)
    self:drawRect(SIDEBAR_WIDTH, BODY_TOP + 1, 1, h - BODY_TOP - 2, 1.0, c.border.r, c.border.g, c.border.b)

    -- Nav items, drawn from the visible-section set each frame. The row pitch is
    -- derived from the available sidebar height, so the list can never overflow the
    -- window no matter the tab count, UI scale or (resized) window height. Group
    -- captions take their height out of that budget before the rows share the rest.
    local body, footer = self:cachedNavRows()
    local nx, nw = 8, SIDEBAR_WIDTH - 16
    local capH = navCaptionH()
    local nCaptions, nRows = 0, 0
    for _, e in ipairs(body) do
        if e.caption then nCaptions = nCaptions + 1 else nRows = nRows + 1 end
    end
    local footerH = #footer * (NAV_ITEM_H + NAV_GAP)
    local availH = (h - (WINDOW_RADIUS + 8)) - NAV_TOP - footerH - nCaptions * capH
    local pitch = math.min(NAV_ITEM_H + NAV_GAP, (nRows > 0) and (availH / nRows) or (NAV_ITEM_H + NAV_GAP))
    local itemH = math.max(20, math.min(NAV_ITEM_H, pitch - NAV_GAP))
    local activeY
    self.navRects = {}

    -- One drawer for both lists: the footer rows are ordinary nav rows, they are just
    -- laid out from the sidebar's bottom instead of from the top.
    local hoverIndex = 0
    local function drawRow(sec, ny)
        hoverIndex = hoverIndex + 1
        local hovered = self:isMouseOver()
            and self:getMouseX() >= nx and self:getMouseX() <= nx + nw
            and self:getMouseY() >= ny and self:getMouseY() <= ny + itemH
        self.navHoverT[hoverIndex] = UI.glide(self.navHoverT[hoverIndex] or 0, hovered and 1 or 0, 0.3)
        local active = self.activeSection == sec.key
        if active then activeY = ny end
        if active then
            UI.roundRect(self, nx, ny, nw, itemH, 8, 0.16, c.accent)
        elseif self.navHoverT[hoverIndex] > 0.01 then
            UI.roundRect(self, nx, ny, nw, itemH, 8, 0.6 * self.navHoverT[hoverIndex], c.panel2)
        end
        -- The redesign's nav row: a status dot rather than an icon, so the eye
        -- follows the labels and the accent reads as the only state in the column.
        local dotCol = active and c.accent or c.faint
        local textCol = active and c.text or c.dim
        local dotY = ny + math.floor((itemH - 6) / 2)
        UI.roundRect(self, nx + 12, dotY, 6, 6, 3, 1.0, dotCol)
        -- labelKey routes through FF.text/getText -- the only path proven safe
        -- for accented PT-BR text this session; plain FF.tr(sec.label) stays
        -- the default for every other (English or unaccented) entry.
        local navLabel = sec.labelKey and FF.text(sec.labelKey, sec.label) or FF.tr(sec.label)
        self:drawText(navLabel, nx + 28, ny + math.floor((itemH - UI.fh(UI.font.body)) / 2),
            textCol.r, textCol.g, textCol.b, 1.0, UI.font.body)
        self.navRects[#self.navRects + 1] = { x = nx, y = ny, w = nw, h = itemH, key = sec.key }
    end

    local ny = NAV_TOP
    for _, entry in ipairs(body) do
        if entry.caption then
            -- Caption: decoration only. Deliberately absent from navRects, so it is
            -- not a click target and the click routing below is unchanged.
            self:drawText(FF.tr(entry.caption), nx + 4,
                ny + capH - UI.fh(UI.font.small) - 3,
                c.faint.r, c.faint.g, c.faint.b, 1.0, UI.font.small)
            ny = ny + capH
        else
            drawRow(entry.section, ny)
            ny = ny + pitch
        end
    end

    -- Footer rows, bottom-up, so Settings/Help stay put as the window resizes.
    local fy = h - (WINDOW_RADIUS + 8) - #footer * (NAV_ITEM_H + NAV_GAP)
    for _, entry in ipairs(footer) do
        drawRow(entry.section, fy)
        fy = fy + NAV_ITEM_H + NAV_GAP
    end

    -- Gliding accent indicator beside the active row.
    if activeY then
        if self.indicatorY < 0 then self.indicatorY = activeY end
        self.indicatorY = UI.glide(self.indicatorY, activeY, 0.3)
        UI.roundRect(self, 3, self.indicatorY + math.floor(itemH / 4),
            3, math.max(4, itemH - 16), 1, 1.0, c.accent)
    end

    -- Subtle corner resize grips (the actual hit-zones are the ResizeGrip children).
    local g = c.dim
    self:drawRect(w - 11, h - 5, 7, 2, 0.45, g.r, g.g, g.b)
    self:drawRect(w - 5, h - 11, 2, 7, 0.45, g.r, g.g, g.b)
    self:drawRect(4, h - 5, 7, 2, 0.45, g.r, g.g, g.b)
    self:drawRect(3, h - 11, 2, 7, 0.45, g.r, g.g, g.b)
end

-- Called every frame; throttled to once a second and only while the Raid tab is
-- open, so it re-runs populateRaid() to pick up fresh raidProgress numbers.
function LasciviousFactionsSystemPanel:update()
    if self.collapsed then return end   -- nothing visible to refresh while minimized
    -- Drain a rebuild that arrived inside the throttle window (see requestRebuild).
    if self.pendingRebuild then
        local rnow = getTimestamp and getTimestamp() or nil
        if (not rnow) or (not self.lastRebuildAt) or (rnow - self.lastRebuildAt) >= REBUILD_INTERVAL then
            self:rebuildNow()
        end
    end
    if self.activeSection == "claims" then
        self:refreshClaimControls()
        return
    end
    local now = getTimestamp()
    if not (self.activeSection == "factions" and self.factionsSubTab == "raid") then return end
    if self.nextRaidRefresh and now < self.nextRaidRefresh then return end
    self.nextRaidRefresh = now + 1

    local player = getPlayer()
    if not player then return end
    local name, faction = FF.getFactionOfPlayer(player:getUsername())
    if not faction then return end
    local isDefending = faction.raid ~= nil
    local isAttacking = false
    for _, other in pairs(FF.getData().factions or {}) do
        if other.raid and other.raid.attacker == name then isAttacking = true break end
    end
    if isDefending or isAttacking then
        self:showSection("raid")
    end
end

function LasciviousFactionsSystemPanel:createChildren()
    self.navRects = self.navRects or {}
    self.navHoverT = self.navHoverT or {}
    self.indicatorY = -1

    -- Transparent content pane over the rounded window bg; local (0,0) origin is
    -- preserved so every populateX builder and the claim map keep their coords.
    self.content = ISPanel:new(SIDEBAR_WIDTH + 1, BODY_TOP + 1,
        self:getWidth() - SIDEBAR_WIDTH - 2, self:getHeight() - BODY_TOP - 2)
    self.content.background = false
    -- Clip EVERYTHING in the content area to its rect (the vanilla stencil idiom:
    -- setStencilRect in prerender, clearStencilRect in render -- render runs after
    -- the children, so the stencil covers every child draw). Without this, scrolled
    -- tab content (Help/Settings) paints over the header and past the window edges.
    self.content.prerender = function(s)
        s:setStencilRect(0, 0, s:getWidth(), s:getHeight())
        ISPanel.prerender(s)
    end
    self.content.render = function(s)
        ISPanel.render(s)
        s:clearStencilRect()
    end
    self.content:initialise()
    self.content:instantiate()
    self:addChild(self.content)

    -- Corner resize handles, added after the content pane so they win the hit-test
    -- even where they overlap it. Repositioned by :layoutGrips() on every resize.
    self.resizeGripBR = ResizeGrip:new(0, 0, RESIZE_GRIP, "br", self)
    self.resizeGripBR:initialise(); self.resizeGripBR:instantiate()
    self:addChild(self.resizeGripBR)
    self.resizeGripBL = ResizeGrip:new(0, 0, RESIZE_GRIP, "bl", self)
    self.resizeGripBL:initialise(); self.resizeGripBL:instantiate()
    self:addChild(self.resizeGripBL)
    self:layoutGrips()

    -- Also after the content pane, and for the same reason: it overhangs it.
    self.notifPanel = NotifDropdown:new()
    self.notifPanel:initialise(); self.notifPanel:instantiate()
    self.notifPanel:setVisible(false)
    self:addChild(self.notifPanel)

    -- First time this character ever opens the panel, land on Help so the (large)
    -- feature set is discoverable; every open afterwards defaults to Overview.
    -- Guarded: if a section builder ever errors, the window must still finish opening
    -- (blank content beats a button that appears to do nothing).
    local player = getPlayer()
    local md = player and player:getModData()
    local section = (md and not md.FF_seenHelp) and "help" or "overview"
    if md and section == "help" then md.FF_seenHelp = true end
    self.activeSection = section
    pcall(function() self:showSection(section) end)
end

-- Is (x, y) inside `rect` (a {x,y,w,h} in panel-local space)?
local function inRect(rect, x, y)
    return rect and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

-- Header drag + nav / close hit-testing.
function LasciviousFactionsSystemPanel:onMouseDown(x, y)
    self:bringToTop()
    if inRect(self.bellRect, x, y) then
        self.pendingNotif = true
        return true
    end
    -- Clicks that reach the panel are by definition outside the dropdown (it is a
    -- child and swallows its own), so any of them dismisses it -- and then goes on to
    -- do whatever it was going to do.
    if self.notifOpen then
        self.notifOpen = false
        self:syncNotifPanel()
    end
    if self.closeRect and x >= self.closeRect.x and x <= self.closeRect.x + self.closeRect.w
        and y >= self.closeRect.y and y <= self.closeRect.y + self.closeRect.h then
        self.pendingClose = true
        return true
    end
    if self.minRect and x >= self.minRect.x and x <= self.minRect.x + self.minRect.w
        and y >= self.minRect.y and y <= self.minRect.y + self.minRect.h then
        self.pendingMinimize = true
        return true
    end
    if y <= HEADER_H then
        self.dragging = true
        return true
    end
    return false
end

function LasciviousFactionsSystemPanel:onMouseMove(dx, dy)
    if self.dragging then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
        self.baseY = self.y
    end
end

function LasciviousFactionsSystemPanel:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function LasciviousFactionsSystemPanel:onMouseUp(x, y)
    local wasDragging = self.dragging
    self.dragging = false
    if self.pendingNotif then
        self.pendingNotif = false
        if inRect(self.bellRect, x, y) then
            getSoundManager():playUISound("UIActivateButton")
            self.notifOpen = not self.notifOpen
            -- Opening is the acknowledgement; there is no separate "mark read".
            if self.notifOpen then FF.eventLogUnread = 0 end
            self:syncNotifPanel()
            return true
        end
    end
    if self.pendingClose then
        self.pendingClose = false
        if self.closeRect and x >= self.closeRect.x and x <= self.closeRect.x + self.closeRect.w
            and y >= self.closeRect.y and y <= self.closeRect.y + self.closeRect.h then
            self:close()
            return true
        end
    end
    if self.pendingMinimize then
        self.pendingMinimize = false
        if self.minRect and x >= self.minRect.x and x <= self.minRect.x + self.minRect.w
            and y >= self.minRect.y and y <= self.minRect.y + self.minRect.h then
            self:toggleCollapse()
            return true
        end
    end
    for _, r in ipairs(self.navRects or {}) do
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            getSoundManager():playUISound("UIActivateButton")
            self:showSection(r.key)
            return true
        end
    end
    if wasDragging then self:savePanelState() end
    return false
end

function LasciviousFactionsSystemPanel:onMouseUpOutside(x, y)
    local wasDragging = self.dragging
    self.dragging = false
    self.pendingClose = false
    self.pendingMinimize = false
    self.pendingNotif = false
    -- Clicking away from the window closes the dropdown, the way every other menu of
    -- its kind behaves.
    if self.notifOpen then
        self.notifOpen = false
        self:syncNotifPanel()
    end
    if wasDragging then self:savePanelState() end
end

-- Resize + collapse ----------------------------------------------------------

-- Keep the corner grips glued to the bottom corners after any size change.
function LasciviousFactionsSystemPanel:layoutGrips()
    local w, h = self:getWidth(), self:getHeight()
    if self.resizeGripBR then self.resizeGripBR:setX(w - RESIZE_GRIP); self.resizeGripBR:setY(h - RESIZE_GRIP) end
    if self.resizeGripBL then self.resizeGripBL:setX(0);              self.resizeGripBL:setY(h - RESIZE_GRIP) end
end

-- Apply a new window size: resize the content pane, reposition the grips, and
-- rebuild the active tab (every populateX reads self.content dimensions live, so
-- re-running showSection is a full reflow -- same path the live-sync listener uses).
function LasciviousFactionsSystemPanel:onResized(newW, newH)
    self:setWidth(newW)
    self:setHeight(newH)
    if self.content then
        self.content:setWidth(newW - SIDEBAR_WIDTH - 2)
        self.content:setHeight(newH - BODY_TOP - 2)
    end
    self:layoutGrips()
    if self.activeSection and not self.collapsed then
        pcall(function() self:showSection(self.activeSection) end)
    end
end

-- Called by the corner grips with clean incremental mouse deltas. Does the min /
-- screen clamping; the bottom-left corner also shifts X so the right edge stays put.
function LasciviousFactionsSystemPanel:resizeByDelta(corner, dx, dy)
    self._resizing = true
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x, y = self:getX(), self:getY()
    local w, h = self:getWidth(), self:getHeight()

    -- Screen clamp first, minimum clamp last, so the result is never below the
    -- minimum (and never negative) even if the window was dragged partly off-screen.
    local newH = h + dy
    if y + newH > screenH then newH = screenH - y end
    if newH < MIN_WINDOW_HEIGHT then newH = MIN_WINDOW_HEIGHT end

    local newW = w
    if corner == "br" then
        newW = w + dx
        if x + newW > screenW then newW = screenW - x end
        if newW < MIN_WINDOW_WIDTH then newW = MIN_WINDOW_WIDTH end
    else   -- "bl": keep the right edge fixed, move the left edge
        local right = x + w
        newW = w - dx
        if newW < MIN_WINDOW_WIDTH then newW = MIN_WINDOW_WIDTH end   -- clamp width first
        local newX = right - newW                                    -- ...so the right edge stays put
        if newX < 0 then newX = 0; newW = right end                  -- don't cross the screen's left edge
        self:setX(newX)
    end

    self:onResized(newW, newH)
    self.baseY = self:getY()
end

function LasciviousFactionsSystemPanel:endResize()
    self._resizing = false
    self:savePanelState()
end

-- Minimize: collapse to just the header bar (content + grips hidden), or restore.
function LasciviousFactionsSystemPanel:toggleCollapse()
    if self.collapsed then
        self.collapsed = false
        -- Restore the resize floor BEFORE resizing back up (setHeight clamps to it).
        self.minimumHeight = MIN_WINDOW_HEIGHT
        if self.content then self.content:setVisible(true) end
        if self.resizeGripBR then self.resizeGripBR:setVisible(true) end
        if self.resizeGripBL then self.resizeGripBL:setVisible(true) end
        self:onResized(self:getWidth(), self.restoreHeight or WINDOW_HEIGHT)
    else
        self.collapsed = true
        self.restoreHeight = self:getHeight()
        if self.content then self.content:setVisible(false) end
        if self.resizeGripBR then self.resizeGripBR:setVisible(false) end
        if self.resizeGripBL then self.resizeGripBL:setVisible(false) end
        -- ISUIElement:setHeight clamps to self.minimumHeight (MIN_WINDOW_HEIGHT). Without
        -- lowering the floor here the frame never shrinks -- only the content hides,
        -- leaving a full-size empty window. Drop the floor to the collapsed height so the
        -- shrink actually takes; toggleCollapse's restore branch puts it back.
        self.minimumHeight = COLLAPSED_H
        self:setHeight(COLLAPSED_H)
        self:layoutGrips()
    end
    self:savePanelState()
end

-- Remember the window's size/position/collapsed state per character.
function LasciviousFactionsSystemPanel:savePanelState()
    local p = getPlayer()
    if not p then return end
    local md = p:getModData()
    if not md then return end
    local h = self.collapsed and (self.restoreHeight or WINDOW_HEIGHT) or self:getHeight()
    md.FF_panelState = {
        w = math.floor(self:getWidth()),
        h = math.floor(h),
        x = math.floor(self:getX()),
        y = math.floor(self:getY()),
        collapsed = self.collapsed and true or false,
    }
end

function LasciviousFactionsSystemPanel:showSection(key)
    -- Legacy keys ("roles" / "relations" / "leaderboard" / "raid") resolve to the
    -- section that now hosts them, plus the sub-view to open once there.
    local alias = SECTION_ALIAS[key]
    if alias then
        if alias.showRoles then self.showRoles = true end
        if alias.subTab then self.factionsSubTab = alias.subTab end
        key = alias.section
    end
    self.activeSection = key
    -- Keep the interface chrome on the server's purple identity. Faction colours are
    -- still used where they carry gameplay meaning (territory, emblem and directory).
    UI.setAccent(UI.brandAccent)
    -- Every section builder below tears down and recreates its scroll pane from
    -- scratch (self.content:clearChildren() a line down), which would otherwise
    -- reset scroll position to the top on every rebuild -- including the ones
    -- driven by a registry sync while a player is mid-scroll. See UI.captureScroll.
    local restoreScroll = UI.captureScroll(self.activeScroll)
    self.activeScroll = nil
    self.content:clearChildren()
    -- Section builders lay out from sectionTop and may suppress the faction
    -- header; the Factions sub-tabs set both before delegating. Reset per switch.
    self.sectionTop = 0
    self.suppressHeader = false
    -- Each tab claims the header's action slot for itself, or leaves it empty.
    self.headerActionSpec = nil
    -- Guarded, because a builder that throws half-way used to leave the tab holding
    -- whatever it had managed to add and nothing else -- which reads as "this tab is
    -- just empty", not as a crash. The Raid tab shipped broken for four releases that
    -- way: the only evidence was a console trace no player ever looks at.
    local ok, err = pcall(function()
        if key == "overview" then self:populateOverview()
        elseif key == "members" then self:populateMembers()
        elseif key == "claims" then self:populateClaims()
        elseif key == "upgrades" then self:populateUpgrades()
        elseif key == "vehicles" then self:populateVehicles()
        elseif key == "tribute" then self:populateTribute()
        elseif key == "factions" then self:populateFactions()
        elseif key == "settings" then self:populateSettings()
        elseif key == "help" then self:populateHelp()
        elseif key == "debug" then self:populateDebug()
        end
    end)
    -- Record the outcome for /ff admin uitest. Without this the guard above would
    -- blind the very tool built to catch builder crashes: uitest detects them by
    -- pcall'ing showSection, and showSection no longer lets anything through.
    self.sectionError = (not ok) and tostring(err) or nil
    if not ok then
        self:showSectionFailure(key, err)
    else
        -- After sizeScroll/setScrollHeight (called inside the populate builder)
        -- so the restored offset clamps against the real, freshly-measured
        -- content height. Skipped on failure: showSectionFailure clears the
        -- half-built content itself, so there is nothing to restore into.
        restoreScroll(self.activeScroll)
    end
    -- Baseline for the per-frame live-refresh check below (nil on failure, so a
    -- tab that's already showing its own error notice isn't hammered with rebuild
    -- attempts every frame -- see :prerender/liveRefreshFingerprint).
    self._liveRefreshFingerprint = ok and self:liveRefreshFingerprint() or nil
    -- After the builder, so a tab that threw half-way leaves no stale action behind.
    self:syncHeaderAction()
end

-- A section builder threw. Say so on screen and durably in the log.
--
-- This is a reporting aid, NOT a way to swallow the error: pcall already stopped the
-- throw, so without this the failure would be silent. FF.print goes through the
-- AlwaysLogErrors path, so the message survives in the LasciviousFactionsSystem log file long
-- after the console buffer has rolled.
--
-- The partial content is cleared first: a builder that died mid-layout leaves widgets
-- at undefined positions, and a half-drawn tab is exactly what made the Raid bug look
-- like a design choice rather than a crash.
function LasciviousFactionsSystemPanel:showSectionFailure(key, err)
    FF.print("ERROR: building panel section '" .. tostring(key) .. "': " .. tostring(err))
    -- Its own pcall: if drawing the failure notice also throws, we must not recurse.
    pcall(function()
        self.content:clearChildren()
        local note = Notice:new(UI.pad, (self.sectionTop or 0) + 14,
            self.content:getWidth() - 2 * UI.pad,
            "This tab failed to draw. See the LasciviousFactionsSystem log.",
            UI.color.bad, "ic_flame")
        note:initialise()
        self.content:addChild(note)
    end)
end

-- ---------------------------------------------------------------------------
-- Live refresh for data-only tabs.
--
-- Data-only tabs (Overview's "you have no faction yet" vs. the real dashboard,
-- a role's permission checkboxes, the tribute balance/history) used to stay stuck
-- on whatever they looked like the moment the tab was built -- creating a faction,
-- toggling a permission, or a deposit/withdraw (including one from a DIFFERENT
-- member, or the passive per-tick tax) all landed server-side correctly, but
-- nothing ever rebuilt the pane to show it. The header above self.content, by
-- contrast, is drawn fresh every frame straight from FF.getFaction() in
-- :prerender() -- which is exactly why the header could show the right faction
-- while the body sat frozen on "you don't have one".
--
-- An earlier attempt hooked LFS_Client.lua's Events.OnReceiveGlobalModData
-- instead. That event is a NETWORK delivery notification; in singleplayer the
-- client and server share the same in-memory ModData table, and nothing here
-- can be certain the engine fires that event for the local player's own
-- singleplayer actions the way it reliably does over a real connection -- which
-- would explain the fix visibly not working. Reading FF.getData() directly,
-- once per second, has no such dependency: it is the exact same call the header
-- already uses successfully in every mode.
--
-- Cheap on purpose: a short string built from just the fields each tab actually
-- displays, compared against the snapshot showSection() stored when it last
-- (successfully) built the tab. Only computed for the active tab, once per
-- second. Settings (and anything else with a live ISTextEntryBox a player might
-- be mid-edit in) is deliberately excluded from LIVE_REFRESH_SECTIONS, since a
-- rebuild wipes unsent text; Claims is excluded too, since it has its own
-- per-frame live update (refreshClaimControls) plus in-progress drag/draw state
-- a rebuild would interrupt.
-- "vehicles" included, same as every other section here: its own branch
-- below is shaped exactly like "tribute"'s (plain registry contents, no
-- extra time component) -- rebuilds (3D scenes included) ONLY when a
-- protect/lock actually changed, never on a bare timer. The pending-
-- protection COUNTDOWN ticking independently of any real change is handled
-- entirely separately, in :prerender()'s own in-place label update -- see
-- that block's comment for why a fingerprint is the wrong tool for that part.
local LIVE_REFRESH_SECTIONS = { overview = true, members = true, tribute = true, upgrades = true, debug = true,
    vehicles = true }

function LasciviousFactionsSystemPanel:liveRefreshFingerprint()
    local key = self.activeSection
    if not LIVE_REFRESH_SECTIONS[key] then return nil end
    local player = getPlayer()
    local username = player and player:getUsername()
    if not username then return nil end
    local name, faction = FF.getFactionOfPlayer(username)

    if key == "overview" then
        -- Presence + owner is enough: covers "just created/joined" and "left/
        -- disbanded"/ownership transfer. Overview's other stats are cheap to
        -- read but change constantly (score ticks with playtime); the tab
        -- itself already rebuilds correctly once it's showing the right
        -- faction; this fingerprint only needs to catch the identity flip.
        return (name or "") .. "|" .. (faction and tostring(faction.owner) or "")

    elseif key == "tribute" then
        if not faction then return name or "" end
        FF.ensureTribute(faction)
        local t = faction.tribute
        -- lastInterestAmount included separately from balance: a 0-credit
        -- payout (empty treasury) still needs to refresh the pinned "últimas
        -- 24 horas" row's text even though the balance itself didn't move.
        return name .. "|" .. tostring(t.balance) .. "|" .. tostring(#t.history) .. "|" .. tostring(t.ratePercent)
            .. "|" .. tostring(t.lastInterestAmount) .. "|" .. tostring(t.lastInterestAt)

    elseif key == "upgrades" then
        if not faction then return name or "" end
        FF.ensureUpgrades(faction)
        local u = faction.upgrades
        local parts = { name, tostring(u.points), tostring(u.milestonesClaimed), tostring(FF.totalArea(faction.claims)) }
        for _, def in ipairs(FF.UPGRADE_TYPES) do
            parts[#parts + 1] = tostring(FF.upgradeLevel(faction, def.key))
        end
        return table.concat(parts, "|")

    elseif key == "debug" then
        -- The discrete debug bonus (not the live score itself -- see Overview's
        -- own fingerprint above for why that is deliberately excluded), plus both
        -- capture tools' own state so their countdown/finished result refresh
        -- live without needing another button click.
        local accum = FF.wellbeingAccumulation
        local accumSig = accum
            and (tostring(accum.active) .. "|" .. tostring(accum.ticksRemaining) .. "|" .. tostring(accum.activeTicks))
            or "none"
        local vaccum = FF.vehicleMaintAccumulation
        local vaccumSig = vaccum
            and (tostring(vaccum.active) .. "|" .. tostring(vaccum.ticksRemaining) .. "|" .. tostring(vaccum.lostVehicle))
            or "none"
        -- Debug > Caçador's own live-read list -- one part per currently
        -- detected outsider, so a fresh/refreshed/expired circle shows up
        -- without needing to leave and re-enter the tab.
        local hunterSig = "none"
        if faction and faction.hunter and (faction.hunter.detected or faction.hunter.debugLive) then
            local parts = {}
            for uname, entry in pairs(faction.hunter.detected or {}) do
                parts[#parts + 1] = uname .. ":" .. tostring(entry.cx) .. "," .. tostring(entry.cy)
                    .. "," .. tostring(entry.radius) .. "," .. tostring(entry.name ~= nil)
            end
            -- debugLive changes EVERY tick (real position/distance while self-test
            -- is on) even when the circle itself hasn't regenerated -- without this,
            -- the panel would only refresh on an actual circle change, and the new
            -- live position/distance readout would sit frozen.
            for uname, live in pairs(faction.hunter.debugLive or {}) do
                parts[#parts + 1] = "live:" .. uname .. ":" .. tostring(live.px) .. "," .. tostring(live.py)
                    .. "," .. tostring(live.distance)
            end
            table.sort(parts)
            hunterSig = table.concat(parts, ";")
        end
        return (name or "") .. "|" .. tostring(faction and faction.debugPowerBonus or 0)
            .. "|" .. accumSig .. "|" .. vaccumSig .. "|" .. hunterSig

    elseif key == "vehicles" then
        -- Shaped exactly like "tribute" above: plain registry contents, NO
        -- time component at all. Only rebuilds when a protect/lock actually
        -- changed (requestedAt/protectedAt are each set once and never
        -- ticked, so including them is safe -- they change only on a real
        -- new request/confirmation, not continuously). The countdown itself
        -- is NOT this fingerprint's job -- see :prerender()'s separate
        -- in-place label update.
        if not faction then return name or "" end
        FF.ensureVehicleGuard(faction)
        local parts = { name }
        for id, entry in pairs(faction.vehicles.protected) do
            parts[#parts + 1] = tostring(id) .. ":" .. tostring(entry.protectedAt) .. ":" .. tostring(entry.requestedAt)
        end
        for id in pairs(faction.vehicles.locked) do
            parts[#parts + 1] = "L" .. tostring(id)
        end
        table.sort(parts)
        return table.concat(parts, "|")

    elseif key == "members" then
        if not faction then return name or "" end
        -- Roster size catches joins/kicks; walking every role's permission flags
        -- catches a manageTribute-style checkbox toggle (this tab's other
        -- reported bug) without needing a separate mechanism for it.
        local parts = { name, tostring(FF.memberCount(faction)) }
        if faction.roles then
            for roleName, perms in pairs(faction.roles) do
                parts[#parts + 1] = roleName
                for _, perm in ipairs(FF.PERMISSIONS) do
                    parts[#parts + 1] = perms[perm] and "1" or "0"
                end
            end
        end
        return table.concat(parts, "|")
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Factions: the directory plus the three faction-vs-faction views, behind one
-- sub-tab strip. Each sub-view is an unchanged section builder, laid out below
-- the strip via sectionTop / suppressHeader (the strip already names the tab, so
-- repeating the player's own emblem under it would be noise).
-- ---------------------------------------------------------------------------
function LasciviousFactionsSystemPanel:populateFactions()
    local tabs = self:visibleFactionSubTabs()
    local valid = false
    for _, t in ipairs(tabs) do if t.key == self.factionsSubTab then valid = true end end
    if not valid then self.factionsSubTab = tabs[1] and tabs[1].key or "directory" end

    self:addLabel(UI.pad, 12, "Factions", UI.color.text, UI.font.title)
    local strip = FFSubTabs:new(UI.pad, 12 + UI.fh(UI.font.title) + 10, tabs,
        self.factionsSubTab, self, LasciviousFactionsSystemPanel.onFactionSubTab)
    strip:initialise(); strip:instantiate()
    self.content:addChild(strip)

    self.sectionTop = strip:getY() + strip:getHeight() + 6
    self.suppressHeader = true

    local sub = self.factionsSubTab
    if sub == "relations" then self:populateRelations()
    elseif sub == "leaderboard" then self:populateLeaderboard()
    elseif sub == "raid" then self:populateRaid()
    else self:populateDirectory() end
end

function LasciviousFactionsSystemPanel:onFactionSubTab(key)
    self.factionsSubTab = key
    self:showSection("factions")
end

-- ---------------------------------------------------------------------------
-- Factions > Directory: every faction on the server, with the selected one's
-- claim size, roster and PvP record. Read-only, and read entirely from
-- the replicated registry -- the same data the leaderboard already surfaces.
-- ---------------------------------------------------------------------------
function LasciviousFactionsSystemPanel:populateDirectory()
    local opts = FF.getOptions()
    local x = UI.pad
    local y = self.sectionTop or 0
    local innerW = self.content:getWidth() - 2 * UI.pad
    self.directoryMyName = self:playerFactionName()

    -- Rank by the same weighted score the leaderboard uses, so "#2 - 1180" here
    -- and the Leaderboard tab can never disagree.
    local rows = {}
    for fname, faction in pairs(FF.getData().factions or {}) do
        rows[#rows + 1] = { name = fname, faction = faction,
            score = FF.factionScore(faction, opts, fname) }
    end
    table.sort(rows, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    for i, row in ipairs(rows) do row.rank = i end

    if #rows == 0 then
        local note = Notice:new(x, y, innerW, "No factions exist yet.", UI.color.dim, nil)
        note:initialise(); self.content:addChild(note)
        return
    end

    -- Default the selection to the player's own faction, then the top of the list.
    local byName = {}
    for _, row in ipairs(rows) do byName[row.name] = row end
    if not (self.directorySelected and byName[self.directorySelected]) then
        self.directorySelected = (self.directoryMyName and byName[self.directoryMyName])
            and self.directoryMyName or rows[1].name
    end

    local listW = math.min(240, math.floor(innerW * 0.38))
    local listH = self.content:getHeight() - y - UI.pad

    self.directoryList = ISScrollingListBox:new(x, y, listW, listH)
    self.directoryList.backgroundColor = UI.color.panel
    self.directoryList:initialise(); self.directoryList:instantiate()
    self.directoryList.itemheight = 5 + UI.lineH(UI.font.body) + UI.lineH(UI.font.small) + 4   -- two lines of text per row
    self.directoryList.font = UI.font.body
    self.directoryList.drawBorder = true
    self.directoryList.borderColor = UI.color.border
    self.directoryList.doDrawItem = LasciviousFactionsSystemPanel.drawDirectoryRow
    self.directoryList.target = self
    self.directoryList.onmousedown = LasciviousFactionsSystemPanel.onDirectoryRowClicked
    for i, row in ipairs(rows) do
        local f = row.faction
        self.directoryList:addItem(row.name, {
            name = row.name,
            meta = FF.text("UI_LFS_DirectoryMeta", "%d pts - %d members - %d tiles",
                math.floor(FF.factionScore(f, opts) + 0.5), FF.memberCount(f),
                FF.totalArea(f.claims)),
            color = UI.factionColor(row.name),
        })
        if row.name == self.directorySelected then self.directoryList.selected = i end
    end
    self.content:addChild(self.directoryList)

    self:buildDirectoryDetail(x + listW + 14, y, innerW - listW - 14, listH,
        byName[self.directorySelected], opts)
end

function LasciviousFactionsSystemPanel.drawDirectoryRow(self, y, item, alt)
    local h, w = self.itemheight, self:getWidth()
    local row = item.item
    local selected = (self.selected == item.index)
    local hover = (self.mouseoverselected == item.index) and self:isMouseOver()
    if selected then
        local a = UI.color.accent
        self:drawRect(0, y, w, h, 0.16, a.r, a.g, a.b)
        self:drawRect(0, y, 3, h, 1.0, a.r, a.g, a.b)
    elseif hover then
        self:drawRect(0, y, w, h, 1.0, UI.color.panel2.r, UI.color.panel2.g, UI.color.panel2.b)
    end
    -- Emblem square carrying the faction's initials, in the same name-derived colour
    -- the panel header, claim overlay and map markers use -- so a faction is the same
    -- mark everywhere. This was an 8px dot, which carried the colour but not the
    -- identity, and left the row with nothing to scan down.
    local tx = drawRowAvatar(self, 12, y, h, row.name, row.color)
    local nameC = selected and UI.color.text or UI.color.text2
    local budget = w - tx - 12
    local blockH = UI.fh(UI.font.body) + 2 + UI.fh(UI.font.small)
    local ty = y + math.floor((h - blockH) / 2)
    self:drawText(UI.fit(UI.font.body, row.name, budget), tx, ty,
        nameC.r, nameC.g, nameC.b, 1.0, UI.font.body)
    self:drawText(UI.fit(UI.font.small, row.meta, budget), tx, ty + UI.fh(UI.font.body) + 2,
        UI.color.faint.r, UI.color.faint.g, UI.color.faint.b, 1.0, UI.font.small)
    return y + h
end

function LasciviousFactionsSystemPanel:onDirectoryRowClicked(row)
    if row and row.name and row.name ~= self.directorySelected then
        self.directorySelected = row.name
        self:showSection("factions")   -- rebuild the pane for the new selection
    end
end

-- The right-hand detail card. Everything lives in a scroll pane because a large
-- faction's roster can easily outrun the card.
function LasciviousFactionsSystemPanel:buildDirectoryDetail(x, y, w, h, row, opts)
    local card = FFCard:new(x, y, w, h)
    card:initialise(); card:instantiate(); self.content:addChild(card)

    if not row then
        cardText(card, 14, 16, "Select a faction on the left.", UI.color.faint)
        return
    end

    local scroll = ISPanel:new(1, 1, w - 2, h - 2)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    card:addChild(scroll)
    self.activeScroll = scroll

    local faction = row.faction
    local pad, colW = 14, w - 2 - 14 - 20   -- minus the scrollbar gutter
    local cy = 14
    local lh = UI.fh(UI.font.body) + 2

    -- Title row: colour chip, name, score badge.
    local chip = ISPanel:new(pad, cy + 3, 14, 14)
    chip.background = false
    local chipColor = UI.factionColor(row.name)
    chip.prerender = function(s) UI.roundRect(s, 0, 0, 14, 14, 4, 1.0, chipColor) end
    chip:initialise(); scroll:addChild(chip)
    local shownName = UI.fit(UI.font.title, row.name, colW - 90)
    cardText(scroll, pad + 22, cy, shownName, UI.color.text, UI.font.title)
    do
        local lvl = FFBadge:new(pad + 22 + UI.tw(UI.font.title, shownName) + 10, cy + 2,
            tostring(math.floor(row.score + 0.5)) .. " pts", { fill = UI.color.accent })
        lvl:initialise(); scroll:addChild(lvl)
    end
    cy = cy + UI.fh(UI.font.title) + 6

    local desc = (type(faction.description) == "string" and faction.description ~= "")
        and faction.description or "No description."
    for _, line in ipairs(wrapText(desc, UI.font.body, colW)) do
        cardText(scroll, pad, cy, line, UI.color.text2)
        cy = cy + lh
    end
    cy = cy + 10

    -- Three-up stat strip: claim size / members / leaderboard standing.
    local statW = math.floor(colW / 3)
    local stats = {
        { "CLAIM SIZE", FF.totalArea(faction.claims) .. " tiles" },
        { "MEMBERS", tostring(FF.memberCount(faction)) },
        { "LEADERBOARD", string.format("#%d  -  %d", row.rank, math.floor(row.score + 0.5)) },
    }
    for i, s in ipairs(stats) do
        local sx = pad + (i - 1) * statW
        cardText(scroll, sx, cy, s[1], UI.color.accent, UI.font.small)
        cardText(scroll, sx, cy + UI.lineH(UI.font.small), s[2], UI.color.text, UI.font.body)
    end
    cy = cy + UI.lineH(UI.font.small) + lh + 12

    local function heading(text)
        cardText(scroll, pad, cy, text, UI.color.accent, UI.font.small)
        cy = cy + UI.fh(UI.font.small) + 4
    end

    heading("MEMBERS")
    local names = {}
    for member in pairs(faction.members or {}) do names[#names + 1] = member end
    table.sort(names)
    for _, line in ipairs(wrapText(#names > 0 and table.concat(names, ", ") or "None", UI.font.body, colW)) do
        cardText(scroll, pad, cy, line, UI.color.text2)
        cy = cy + lh
    end
    cy = cy + 10

    heading("PVP RECORD")
    -- Read-only: never FF.ensureStats() here. That would write a zeroed table into
    -- the replicated registry from a client just for a display, and the server is
    -- the authority on this counter set.
    local st = faction.stats or {}
    cardText(scroll, pad, cy, string.format("%d raids won  -  %d lost  -  %d defended",
        st.raidsWon or 0, st.raidsLost or 0, st.raidsDefended or 0), UI.color.text2)
    cy = cy + lh + 14

    -- Vehicles: same used/limit reading the Veículos tab's own info banner uses
    -- (FF.vehicleProtectionCount/Limit, shared/LFS_VehicleGuard.lua) -- reads
    -- ANY faction's replicated data directly, not the current player's loaded-
    -- world state, so this works browsing a faction you're not even in.
    heading(FF.text("UI_LFS_DirectoryVehiclesHeading", "VEÍCULOS"))
    local vOpts = FF.getOptions()
    local vLimit = FF.vehicleProtectionLimit(faction, vOpts)
    local vUsed = FF.vehicleProtectionCount(faction)
    cardText(scroll, pad, cy,
        FF.text("UI_LFS_VehiclesInfo", "Vagas de proteção usadas: %s / %s.", tostring(vUsed), tostring(vLimit)),
        UI.color.text2)
    cy = cy + lh + 14

    -- Upgrades: every track + its current level, in catalog order, so a member
    -- browsing another faction can see at a glance what they've invested in --
    -- same FF.UPGRADE_TYPES/FF.upgradeLevel the Aprimoramentos tab itself reads.
    heading(FF.text("UI_LFS_DirectoryUpgradesHeading", "APRIMORAMENTOS"))
    local upgradeParts = {}
    for _, def in ipairs(FF.UPGRADE_TYPES) do
        local lvl = FF.upgradeLevel(faction, def.key)
        local label = FF.text(def.labelKey, def.labelFallback)
        upgradeParts[#upgradeParts + 1] = FF.text("UI_LFS_DirectoryUpgradeEntry", "%s %d", label, lvl)
    end
    for _, line in ipairs(wrapText(table.concat(upgradeParts, "  -  "), UI.font.body, colW)) do
        cardText(scroll, pad, cy, line, UI.color.text2)
        cy = cy + lh
    end
    cy = cy + 14

    scroll:setScrollHeight(cy)
end

-- Shared building blocks -----------------------------------------------------

-- Adds the faction emblem/name/role header and returns the Y the section body
-- should start at. Sections hosted inside another section's sub-tab strip set
-- self.sectionTop (where their body begins) and self.suppressHeader (the strip
-- above already identifies the view) -- both default to "own the whole pane".
function LasciviousFactionsSystemPanel:addHeader(factionName, faction, username)
    -- The hero block this used to add is gone: the window header now carries the
    -- emblem, faction name and role once, for every tab, instead of each tab
    -- re-stating them in a ~50px band above its own content. Kept as the single
    -- funnel every builder already calls, so "where does my body start" has one
    -- answer and sub-tabbed views (sectionTop / suppressHeader) keep working.
    return (self.sectionTop or 0) + 12
end

-- "N online now" for the Members stat tile, or nil when we genuinely cannot tell.
--
-- The registry does not replicate per-member presence; the only live signal a client
-- has is the server's periodic "positions" broadcast, which LFS_Client
-- stores as FF.memberPositions. That broadcast is gated by MemberMarkersEnabled, so on
-- a server with markers off there is no answer -- and nil is the honest one. Inventing
-- "0 online" there would be a lie about the roster, on the panel's opening tile.
function LasciviousFactionsSystemPanel:onlineSubLine(factionName)
    local mp = FF.memberPositions
    if not (mp and mp.factions and factionName) then return nil end
    -- Same staleness window the map overlay applies to these markers.
    if (getTimestamp() - (mp.at or 0)) > 30 then return nil end
    local list = mp.factions[factionName]
    if not list then return nil end
    local n = #list
    return (n == 1) and FF.text("UI_LFS_OnlineOne", "1 online now")
        or FF.text("UI_LFS_OnlineMany", "%d online now", n)
end

-- Returns the NEXT y, not the row -- deliberately. Every caller used to follow this
-- with a hardcoded `+ 22`, which is exactly the hardcoded-pitch bug that broke the
-- panel at large fonts; handing back a coordinate makes that impossible to write.
function LasciviousFactionsSystemPanel:addStatRow(parent, x, y, w, label, value, dotColor)
    local row = StatRow:new(x, y, w, label, value, dotColor)
    row:initialise()
    parent:addChild(row)
    return y + row:getHeight() + 2
end

-- A left-aligned ISLabel added straight to self.content (persists as a child;
-- see the FFBar comment in the toolkit for why one-shot drawText() would not).
function LasciviousFactionsSystemPanel:addLabel(x, y, text, color, font)
    text = FF.tr(text)
    color = color or UI.color.text
    font = font or UI.font.body
    local label = ISLabel:new(x, y, UI.fh(font), text, color.r, color.g, color.b, 1.0, font, true)
    label:initialise()
    self.content:addChild(label)
    return label
end

-- Themed row drawer for name-only lists (join / raid targets).
function LasciviousFactionsSystemPanel.drawSimpleRow(self, y, item, alt)
    local h, w = self.itemheight, self:getWidth()
    local hover = (self.mouseoverselected == item.index) and self:isMouseOver()
    if hover then
        self:drawRect(0, y, w, h, 1.0, UI.color.panel2.r, UI.color.panel2.g, UI.color.panel2.b)
    end
    self:drawText(item.text, 10, y + math.floor((h - UI.fh(UI.font.body)) / 2),
        UI.color.text.r, UI.color.text.g, UI.color.text.b, 1.0, UI.font.body)
    return y + h
end

-- ---------------------------------------------------------------------------
-- Overview
-- ---------------------------------------------------------------------------

function LasciviousFactionsSystemPanel:populateOverview()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:populateOverviewNoFaction()
        return
    end

    local x = UI.pad
    local headerY = self:addHeader(name, faction, username)

    -- The overview overflows the window once wars / season / score cards all show at
    -- once, pushing the action buttons off the bottom with no way to reach them. Host
    -- every card in a scroll pane below the fixed header -- same idiom as the Help and
    -- Settings tabs.
    local scroll = ISPanel:new(0, headerY, self.content:getWidth(), self.content:getHeight() - headerY)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    self.content:addChild(scroll)
    self.overviewScroll = scroll
    self.activeScroll = scroll

    local innerW = self.content:getWidth() - 2 * UI.pad - 16   -- leave room for the scrollbar
    local y = UI.pad

    local opts = FF.getOptions()
    local memberCount = FF.memberCount(faction)
    local claimed = FF.totalArea(faction.claims)
    local maxTiles = FF.maxClaimTiles(FF.factionScore(faction, opts), opts)

    -- War status: one row per active war this faction is fighting (as a principal OR a
    -- coalition member), with a live score bar and (for a principal owner) a surrender
    -- button. Score is principal-vs-principal; coalition allies on our side are listed.
    -- Gathered BEFORE anything is drawn so the at-a-glance and war cards can share the
    -- redesign's two-column top row (and fall back to one full-width card in peacetime).
    local warRows = {}
    if opts.warsEnabled then
        local function sideOf(war, fn)
            if war.a == fn then return "a" end
            if war.b == fn then return "b" end
            return war.coalition and war.coalition[fn] or nil
        end
        for _, war in pairs(FF.getData().wars or {}) do
            local side = sideOf(war, name)
            if side then
                local myPrincipal = (side == "a") and war.a or war.b
                local oppPrincipal = (side == "a") and war.b or war.a
                local allies = {}
                for member, s in pairs(war.coalition or {}) do
                    if s == side and member ~= name then allies[#allies + 1] = member end
                end
                table.sort(allies)
                warRows[#warRows + 1] = { war = war, myPrincipal = myPrincipal, oppPrincipal = oppPrincipal,
                    iamPrincipal = (myPrincipal == name), allies = allies }
            end
        end
        table.sort(warRows, function(a, b) return a.oppPrincipal < b.oppPrincipal end)
    end

    local atWar = #warRows > 0

    -- The headline numbers as stat tiles. These were "Members: 5" / "Territory: 694 /
    -- 4,900 tiles" rows inside one card, which gave the figure and its label the same
    -- weight -- a form to read rather than a state to glance at. A tile inverts that:
    -- the number is large, its name is a caption. This row is the first thing on the
    -- first tab, so it is the whole panel's opening statement.
    local tiles = {
        { kicker = "Members", value = tostring(memberCount), sub = self:onlineSubLine(name) },
        { kicker = "Territory", value = tostring(claimed),
          valueSuffix = FF.text("UI_LFS_MaxTileSuffix", "/ %d tiles", math.floor(maxTiles + 0.5)),
          fraction = (maxTiles > 0) and (claimed / maxTiles) or 0 },
    }
    if atWar then
        -- The first war only. Coalitions, surrender and the rest stay in the card
        -- below, which can say things a tile cannot; the tile carries the score.
        local r = warRows[1]
        local war = r.war
        local mine = (war.score and war.score[r.myPrincipal]) or 0
        local theirs = (war.score and war.score[r.oppPrincipal]) or 0
        tiles[#tiles + 1] = {
            kicker = "War -- vs " .. r.oppPrincipal,
            value = string.format("%d - %d", mine, theirs),
            valueSuffix = (war.target and war.target > 0) and string.format("first to %d", war.target) or nil,
            fraction = (war.target and war.target > 0) and math.min(1, mine / war.target) or 0,
            barColor = UI.color.warn,
        }
    end
    local tileW = math.floor((innerW - (#tiles - 1) * 10) / #tiles)
    local tileH = 0
    for i, t in ipairs(tiles) do
        local tile = FFStat:new(x + (i - 1) * (tileW + 10), y, tileW, t)
        tile:initialise(); tile:instantiate(); scroll:addChild(tile)
        tileH = math.max(tileH, tile:getHeight())
    end
    y = y + tileH + 10

    if atWar then
        local isOwner = faction.owner == username
        local surrenderW = UI.buttonWidth("Surrender", false, UI.rowH(UI.font.small))
        local colW = innerW
        local wCard = FFCard:new(x, y, colW, 0, "WAR STATUS")
        wCard:initialise(); wCard:instantiate(); scroll:addChild(wCard)
        local wy = wCard:contentTop()
        for _, r in ipairs(warRows) do
            local war = r.war
            local mine = (war.score and war.score[r.myPrincipal]) or 0
            local theirs = (war.score and war.score[r.oppPrincipal]) or 0
            local label = FF.text("UI_LFS_DynamicVs", "vs %s", r.oppPrincipal)
            if not r.iamPrincipal then
                label = FF.text("UI_LFS_CoalitionVs", "vs %s  (coalition, %s)",
                    r.oppPrincipal, r.myPrincipal)
            end
            cardText(wCard, 12, wy, UI.fit(UI.font.body, label, colW - 24), UI.color.text)
            local canSurrender = isOwner and r.iamPrincipal
            if canSurrender then
                local sbtn = FFButton:new(colW - 12 - surrenderW, wy, surrenderW, UI.rowH(UI.font.small),
                    "Surrender", self, LasciviousFactionsSystemPanel.onSurrenderWar, "ghost")
                sbtn.warOpponent = r.oppPrincipal
                sbtn:initialise(); sbtn:instantiate(); wCard:addChild(sbtn)
            end
            wy = wy + math.max(UI.lineH(UI.font.body), canSurrender and UI.rowH(UI.font.small) + 2 or 0)
            cardText(wCard, 12, wy, FF.text("UI_LFS_ScoreFirstTo",
                "%d - %d  (first to %d)", mine, theirs, war.target or 0), UI.color.dim)
            wy = wy + UI.lineH(UI.font.body) + 2
            local wbar = FFBar:new(12, wy, colW - 24, 12)
            wbar:initialise()
            wbar.fraction = (war.target and war.target > 0) and math.min(1, mine / war.target) or 0
            wCard:addChild(wbar)
            wy = wy + 12 + 6
            if #r.allies > 0 then
                cardText(wCard, 12, wy, UI.fit(UI.font.small,
                    FF.text("UI_LFS_DynamicAllies", "allies: %s", table.concat(r.allies, ", ")), colW - 24),
                    UI.color.dim, UI.font.small)
                wy = wy + UI.lineH(UI.font.small)
            end
            wy = wy + 6
        end
        y = y + wCard:setContentHeight(wy) + 10
    end

    -- Season summary: number, time remaining, and the current leader by season score.
    if opts.seasonsEnabled then
        local season = FF.getData().season or {}
        local leader, best
        for fn, f in pairs(FF.getData().factions or {}) do
            local sc = FF.seasonScore(f, opts, fn)
            if not best or sc > best then best, leader = sc, fn end
        end
        local endText = FF.tr("not started")
        if (season.startedAt or 0) > 0 then
            local leftMs = math.max(0, (season.startedAt + math.max(1, opts.seasonLengthDays) * 86400000) - getTimestamp() * 1000)
            endText = string.format("%dd %dh", math.floor(leftMs / 86400000), math.floor(leftMs / 3600000) % 24)
        end
        local sCard = FFCard:new(x, y, innerW, 0, "SEASON")
        sCard:initialise(); sCard:instantiate(); scroll:addChild(sCard)
        local sy = sCard:contentTop()
        sy = self:addStatRow(sCard, 12, sy, innerW - 24, "Season", tostring(season.number or 1), UI.color.accent)
        sy = self:addStatRow(sCard, 12, sy, innerW - 24, "Ends in", endText, UI.color.warn)
        sy = self:addStatRow(sCard, 12, sy, innerW - 24, "Leader",
            leader and string.format("%s (%d)", leader, math.floor((best or 0) + 0.5)) or "-", UI.color.accent)
        y = y + sCard:setContentHeight(sy) + 10
    end

    -- Territory perks: a one-liner reminding members the effects are location-based.
    if (opts.territorySafeZoneEnabled or opts.territoryMoodBuffEnabled or opts.territoryHealthBuffEnabled
        or opts.territoryFatigueBuffEnabled or opts.territoryNeedsBuffEnabled) and claimed > 0 then
        local bits = {}
        if opts.territorySafeZoneEnabled then bits[#bits + 1] = FF.tr("safe zone") end
        if opts.territoryMoodBuffEnabled then bits[#bits + 1] = FF.text("UI_LFS_HomeMood", "humor") end
        if opts.territoryHealthBuffEnabled then bits[#bits + 1] = FF.text("UI_LFS_HomeHealth", "saúde") end
        if opts.territoryFatigueBuffEnabled then bits[#bits + 1] = FF.text("UI_LFS_HomeFatigue", "fadiga") end
        if opts.territoryNeedsBuffEnabled then bits[#bits + 1] = FF.text("UI_LFS_HomeNeeds", "necessidades") end
        local note = Notice:new(x, y, innerW,
            FF.text("UI_LFS_TerritoryPerks",
                "Territory perks (%s) apply while you stand in your claim.", table.concat(bits, " + ")),
            UI.color.dim, nil)
        note:initialise(); scroll:addChild(note)
        y = y + note:getHeight() + 8
    end

    -- Message of the day: the owner's notice to members. Only shown when set, wrapped
    -- to the card width so a long note reads as several lines.
    if type(faction.motd) == "string" and faction.motd ~= "" then
        local mlines = wrapText(faction.motd, UI.font.body, innerW - 24)
        local lh = UI.lineH(UI.font.body)
        local mCardH = UI.cardH(UI.cardTop() + #mlines * lh)
        local mCard = FFCard:new(x, y, innerW, mCardH, "NOTICE")
        mCard:initialise(); mCard:instantiate(); scroll:addChild(mCard)
        local my = mCard:contentTop()
        for _, line in ipairs(mlines) do
            local ml = ISLabel:new(12, my, lh, line, UI.color.text.r, UI.color.text.g, UI.color.text.b, 1.0, UI.font.body, true)
            ml:initialise(); mCard:addChild(ml)
            my = my + lh
        end
        y = y + mCardH + 10
    end

    -- Faction score: the ONLY progression concept left in this mod -- the live sum of
    -- every CURRENT member's current-character kill/survival totals (FF.factionScore). It
    -- drives claim size (maxTiles above) and the leaderboard alike, so it is drawn as
    -- the headline number here rather than buried in a stat row.
    do
        local score = FF.factionScore(faction, opts)
        local scCard = FFCard:new(x, y, innerW, 0, "FACTION SCORE")
        scCard.kickerColor = UI.color.accent
        scCard:initialise(); scCard:instantiate(); scroll:addChild(scCard)
        local scy = scCard:contentTop()

        cardText(scCard, 12, scy, tostring(math.floor(score + 0.5)), UI.color.accent, UI.font.big)
        scy = scy + UI.fh(UI.font.big) + 4
        cardText(scCard, 12, scy,
            UI.fit(UI.font.small, "Soma das mortes de zumbis + horas sobrevividas do personagem atual de cada membro.", innerW - 24),
            UI.color.dim, UI.font.small)
        scy = scy + UI.lineH(UI.font.small) + 8

        -- Top individual contributors -- purely informational (no IO, pure registry
        -- read), so the members carrying the faction's score are easy to spot.
        local ranked = {}
        for user in pairs(faction.members or {}) do
            ranked[#ranked + 1] = { user = user, score = FF.playerScore(user, opts) }
        end
        table.sort(ranked, function(a, b) return a.score > b.score end)
        if #ranked > 0 then
            cardText(scCard, 12, scy, "TOP CONTRIBUTORS", UI.color.dim, UI.font.small)
            scy = scy + UI.lineH(UI.font.small) + 2
            for i = 1, math.min(5, #ranked) do
                local r = ranked[i]
                scy = self:addStatRow(scCard, 12, scy, innerW - 24, r.user,
                    tostring(math.floor(r.score + 0.5)), UI.color.accent)
            end
        end

        y = y + scCard:setContentHeight(scy + 2) + 10
    end

    local strip
    if faction.raid then
        strip = Notice:new(x, y, innerW, "Under attack by " .. tostring(faction.raid.attacker), UI.color.bad, "ic_flame")
    else
        strip = Notice:new(x, y, innerW, "No active raid.", UI.color.dim, nil)
    end
    strip:initialise(); scroll:addChild(strip)
    y = y + strip:getHeight() + 12

    -- Two equal-width block buttons filling the row, as the design has them: this is
    -- the bottom of the first tab, and a pair of buttons hugging their own labels at
    -- the left edge read as an afterthought rather than as the tab's conclusion.
    local BH = UI.rowH(UI.font.body) + 6
    local isOwner = faction.owner == username
    local halfW = math.floor((innerW - 10) / 2)
    local manageBtn = FFButton:new(x, y, halfW, BH, "Manage claim", self,
        LasciviousFactionsSystemPanel.onManageClaimClick, "primary", "ic_claims")
    manageBtn:initialise(); manageBtn:instantiate(); scroll:addChild(manageBtn)

    -- The server rejects an owner's "leave" (owner_must_disband), so an owner never
    -- gets a Leave button that would always fail. Disband is no longer the substitute:
    -- it lives in Settings' danger zone now, where the consequences are spelled out
    -- instead of sitting one slot away from "Manage claim". An owner who can invite
    -- gets the invite action here; otherwise the row is the single primary button.
    local canInvite = FF.roleCan(faction, username, "manageMembers")
    if isOwner then
        if canInvite then
            local inviteBtn = FFButton:new(x + halfW + 10, y, halfW, BH, "Invite member",
                self, LasciviousFactionsSystemPanel.onInviteClick, "ghost", "ic_invite")
            inviteBtn:initialise(); inviteBtn:instantiate(); scroll:addChild(inviteBtn)
        else
            manageBtn:setWidth(innerW)
        end
    else
        local leaveBtn = FFButton:new(x + halfW + 10, y, halfW, BH, "Leave faction",
            self, LasciviousFactionsSystemPanel.onLeaveClick, "ghost")
        leaveBtn:initialise(); leaveBtn:instantiate(); scroll:addChild(leaveBtn)
    end
    y = y + BH + UI.pad

    scroll:setScrollHeight(y)
end

function LasciviousFactionsSystemPanel:onManageClaimClick()
    self:showSection("claims")
end

function LasciviousFactionsSystemPanel:populateOverviewNoFaction()
    local x = UI.pad
    local innerW = self.content:getWidth() - 2 * UI.pad
    self:addLabel(x, 14, "You're not in a faction.", UI.color.text, UI.font.title)

    local BH = UI.rowH(UI.font.body)
    local cby = 14 + UI.lineH(UI.font.title) + 8
    local createW = math.max(200, UI.buttonWidth("Create faction", true, BH))
    local createBtn = FFButton:new(x, cby, createW, BH,
        "Create faction", self, LasciviousFactionsSystemPanel.onOpenCreateDialog, "primary", "ic_claim")
    createBtn.disabledNeutral = true
    createBtn:initialise(); createBtn:instantiate(); self.content:addChild(createBtn)
    local canCreate = factionCreationRequirement()
    createBtn:setEnable(canCreate)
    -- Explain the creation gate before the invitation guidance. Previously the
    -- server rejected the request only after the player had filled the whole modal,
    -- which made the disappearing window look like a broken mod.
    local requirement = CreationRequirement:new(x, cby + BH + 8, innerW, createBtn)
    requirement:initialise(); requirement:instantiate(); self.content:addChild(requirement)
    local note = Notice:new(x, requirement:getBottom() + 12, innerW,
        FF.text("UI_LFS_InvitationOnlyGuidance",
            "To join a faction, wait for a manual invitation from an authorised member."),
        UI.color.dim, "ic_invite")
    note:initialise(); self.content:addChild(note)
end

function LasciviousFactionsSystemPanel:onOpenCreateDialog(button)
    -- Defensive check for scripted calls or a score reset between two UI frames.
    -- The visible button is already disabled by CreationRequirement.
    if not factionCreationRequirement() then return end
    local d = FactionCreateDialog:new()
    d:initialise(); d:instantiate(); d:addToUIManager()
end

function LasciviousFactionsSystemPanel:onAcceptInvite(button)
    if button.inviteFaction then send("acceptInvite", { name = button.inviteFaction }) end
end

function LasciviousFactionsSystemPanel:onDeclineInvite(button)
    if button.inviteFaction then send("declineInvite", { name = button.inviteFaction }) end
end

function LasciviousFactionsSystemPanel:onLeaveClick(button)
    local modal = ISModalDialog:new(0, 0, 320, 130,
        FF.tr("Leave your faction? You'll need an invite to rejoin an invite-only faction."),
        true, self, LasciviousFactionsSystemPanel.onLeaveConfirm)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end

function LasciviousFactionsSystemPanel:onLeaveConfirm(button)
    if button.internal == "YES" then send("leave") end
end

function LasciviousFactionsSystemPanel:onDisbandClick(button)
    local modal = ISModalDialog:new(0, 0, 320, 130,
        FF.tr("Disband your faction? This cannot be undone."), true, self,
        LasciviousFactionsSystemPanel.onDisbandConfirm)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end

function LasciviousFactionsSystemPanel:onDisbandConfirm(button)
    if button.internal == "YES" then send("disband") end
end

-- ---------------------------------------------------------------------------
-- Members
-- ---------------------------------------------------------------------------
function LasciviousFactionsSystemPanel:populateMembers()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end

    local x = UI.pad
    local innerW = self.content:getWidth() - 2 * UI.pad
    local y = self:addHeader(name, faction, username)

    self.membersFactionName = name
    self.selectedMember = nil
    -- Drop last build's handles: content:clearChildren() already destroyed those
    -- widgets, and onMemberRowClicked would otherwise poke at dead references
    -- when this rebuild doesn't recreate them (a viewer without manageMembers).
    self.assignBtn, self.kickBtn, self.transferBtn = nil, nil, nil
    FF.ensureRoles(faction)
    self.canManageMembers = FF.roleCan(faction, username, "manageMembers")
    self.isOwnerViewer = (faction.owner == username)

    -- Roles moved in here as a side pane (the redesign folds the old Roles tab
    -- into Members): the toggle reveals a column of role permissions beside the
    -- roster, so you can read who has what without changing tabs.
    local rolesW = math.min(280, math.floor(innerW * 0.45))
    local showRoles = self.showRoles and true or false
    local listW = showRoles and (innerW - rolesW - 14) or innerW

    -- "+ Invite" is this tab's one headline action, so it goes to the window header's
    -- action slot where every tab's primary action lives. The roles toggle stays on the
    -- tab: it changes what THIS tab shows rather than doing something to the faction.
    if self.canManageMembers then
        self:setHeaderAction("+ Invite", LasciviousFactionsSystemPanel.onInviteClick, "primary")
    end

    -- Roster count and the roles toggle share a title row above the list. The count is
    -- the thing the mockup leads with -- "5 members" states what you are looking at,
    -- where the old tab jumped straight into an unlabelled list.
    local TGH = UI.rowH(UI.font.small)
    local toggleW = math.max(UI.buttonWidth("Hide roles", false, TGH), UI.buttonWidth("Manage roles", false, TGH))
    local toggle = FFButton:new(x + innerW - toggleW, y, toggleW, TGH,
        showRoles and "Hide roles" or "Manage roles", self, LasciviousFactionsSystemPanel.onToggleRolesPane, "ghost")
    toggle:initialise(); toggle:instantiate(); self.content:addChild(toggle)

    local memberCount = FF.memberCount(faction)
    local countText = (memberCount == 1) and "1 member" or string.format("%d members", memberCount)
    self:addLabel(x, y + math.floor((TGH - UI.fh(UI.font.body)) / 2),
        UI.fit(UI.font.body, countText, innerW - toggleW - 20), UI.color.text, UI.font.body)
    y = y + TGH + 8

    -- Action-button geometry, needed before the list so its height can reserve room.
    -- The button height, the reserve below the list, and the per-row pitch all derive
    -- from the same value: converting only some of them clips the buttons off the
    -- bottom of the tab at ANY font size, not just large ones.
    local ABH = UI.rowH(UI.font.body)
    local actionRowPitch = ABH + 8
    local listH = self.content:getHeight() - y - (self.canManageMembers and (ABH + 16) or 12)
    -- Roster actions, declared up here because how many rows they need decides how
    -- tall the list can be. The row count comes from the measured labels rather than
    -- a fixed "listW < 380" guess, which mis-predicts at other UI scales.
    -- Every button here acts on the SELECTED member, which is why they all start
    -- disabled with a "select a member first" tooltip. Invite used to sit among them
    -- and was the one that did not -- it needs no selection, and it was the only
    -- always-enabled button in a row of dead ones. It now lives in the header's action
    -- slot, where the tab's headline action belongs.
    local memberActions = {
        { "assignBtn",   "Assign role", LasciviousFactionsSystemPanel.onAssignRoleClick, "ghost",   "ic_star" },
        { "kickBtn",     "Kick",        LasciviousFactionsSystemPanel.onKickClick,       "danger",  "ic_kick" },
    }
    if self.isOwnerViewer then
        memberActions[#memberActions + 1] = { "transferBtn", "Transfer", LasciviousFactionsSystemPanel.onTransferClick, "ghost", "ic_crown" }
    end
    local widestAction = 0
    for _, d in ipairs(memberActions) do
        widestAction = math.max(widestAction, UI.buttonWidth(d[2], true, ABH))
    end
    local perRow = #memberActions
    while perRow > 1 and (widestAction * perRow + 10 * (perRow - 1)) > listW do
        perRow = perRow - 1
    end
    -- Re-balance once the row count is known: 4 actions that only fit 3-across read
    -- better as 2 + 2 than as 3 + 1.
    local buttonRows = math.ceil(#memberActions / perRow)
    perRow = math.ceil(#memberActions / buttonRows)
    if self.canManageMembers and buttonRows > 1 then listH = listH - actionRowPitch * (buttonRows - 1) end
    listH = math.max(60, listH)

    self.memberList = ISScrollingListBox:new(x, y, listW, listH)
    self.memberList.backgroundColor = UI.color.panel
    self.memberList:initialise()
    self.memberList:instantiate()
    -- Two lines of text plus the avatar square, not one line: drawMemberRow now puts
    -- a sub-line under the username. Derived from both so neither can be clipped by
    -- the other at a large font atlas.
    self.memberList.itemheight = math.max(
        UI.fh(UI.font.body) + 2 + UI.fh(UI.font.small),
        UI.fh(UI.font.body) + 8) + 14
    self.memberList.font = UI.font.body
    self.memberList.drawBorder = true
    self.memberList.borderColor = UI.color.border
    self.memberList.doDrawItem = LasciviousFactionsSystemPanel.drawMemberRow
    self.memberList.target = self
    self.memberList.onmousedown = LasciviousFactionsSystemPanel.onMemberRowClicked
    local memberUsernames = {}
    for memberUsername in pairs(faction.members) do
        table.insert(memberUsernames, memberUsername)
    end
    table.sort(memberUsernames)
    for _, memberUsername in ipairs(memberUsernames) do
        local rname = faction.members[memberUsername]
        local isOwner = (memberUsername == faction.owner)
        local roleTable = faction.roles and faction.roles[rname]
        local hasManage = isOwner or (roleTable ~= nil and roleTable.manageMembers == true)
        self.memberList:addItem(memberUsername, {
            username = memberUsername, role = rname,
            isOwner = isOwner, hasManage = hasManage,
        })
    end
    -- Pending invites appear as dim rows below the members.
    local invitedUsers = {}
    for invitedUser in pairs(faction.invites or {}) do table.insert(invitedUsers, invitedUser) end
    table.sort(invitedUsers)
    for _, invitedUser in ipairs(invitedUsers) do
        self.memberList:addItem(invitedUser, { username = invitedUser, isInvite = true })
    end
    self.content:addChild(self.memberList)

    if self.canManageMembers then
        local by = y + listH + 8
        local bw = math.floor((listW - 10 * (perRow - 1)) / perRow)
        for i, d in ipairs(memberActions) do
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            local btn = FFButton:new(x + col * (bw + 10), by + row * actionRowPitch, bw, ABH, d[2], self, d[3], d[4], d[5])
            btn:initialise(); btn:instantiate()
            btn:setEnable(false)
            btn.tooltip = FF.tr("Select a member first")
            self.content:addChild(btn)
            self[d[1]] = btn
        end
    end

    if showRoles then
        self:buildRolesPane(x + listW + 14, y, rolesW,
            self.content:getHeight() - y - UI.pad, faction, username)
    end
end

function LasciviousFactionsSystemPanel:onToggleRolesPane(button)
    self.showRoles = not self.showRoles
    self:showSection("members")
end

-- The roster row: initials avatar, username, a dim sub-line saying what the row IS,
-- and a role pill hard right.
--
-- This used to be a single line of text with a 14px role icon and the role name in
-- plain small text at the right edge -- so "who is in charge" was carried entirely by
-- a glyph most players never decoded, and the row had no visual anchor to scan down.
-- The avatar gives the eye a column to follow and the pill makes the role a label
-- rather than a decoration.
function LasciviousFactionsSystemPanel.drawMemberRow(self, y, item, alt)
    local h, w = self.itemheight, self:getWidth()
    local m = item.item
    local selected = (self.selected == item.index)
    local hover = (self.mouseoverselected == item.index) and self:isMouseOver()
    if selected then
        self:drawRect(0, y, w, h, 0.16, UI.color.accent.r, UI.color.accent.g, UI.color.accent.b)
        self:drawRect(0, y, 3, h, 1.0, UI.color.accent.r, UI.color.accent.g, UI.color.accent.b)
    elseif hover then
        self:drawRect(0, y, w, h, 1.0, UI.color.panel2.r, UI.color.panel2.g, UI.color.panel2.b)
    end

    local isInvite = m.isInvite
    local roleCol = isInvite and UI.color.dim
        or (m.isOwner and UI.color.accent or (m.hasManage and UI.color.warn or UI.color.dim))
    local nameCol = isInvite and UI.color.dim or UI.color.text

    -- Avatar: initials of the username on its own derived colour, so each member has a
    -- stable, distinguishable mark. Dimmed to a flat square for a pending invite --
    -- they are not a member yet, and the row should not look like they are.
    local tx
    if isInvite then
        local sz = UI.fh(UI.font.body) + 8
        local ay = y + math.floor((h - sz) / 2)
        UI.roundFrame(self, 10, ay, sz, sz, 6, 1.0, UI.color.border, UI.color.panel2)
        UI.drawIcon(self, "ic_invite", 10 + math.floor((sz - 14) / 2), ay + math.floor((sz - 14) / 2),
            14, UI.color.dim)
        tx = 10 + sz + 10
    else
        tx = drawRowAvatar(self, 10, y, h, m.username)
    end

    local pillText = isInvite and FF.tr("INVITED") or FF.tr(m.role or "?")
    local pillX = drawRowPill(self, w - 10, y, h, pillText, roleCol, not isInvite)
    local budget = math.max(0, pillX - 8 - tx)
    local sub = isInvite and "Invitation pending" or (m.isOwner and "Faction owner"
        or (m.hasManage and "Can manage members" or nil))
    if sub then
        local blockH = UI.fh(UI.font.body) + 2 + UI.fh(UI.font.small)
        local ty = y + math.floor((h - blockH) / 2)
        self:drawText(UI.fit(UI.font.body, m.username, budget), tx, ty,
            nameCol.r, nameCol.g, nameCol.b, 1.0, UI.font.body)
        self:drawText(UI.fit(UI.font.small, FF.tr(sub), budget), tx,
            ty + UI.fh(UI.font.body) + 2,
            UI.color.faint.r, UI.color.faint.g, UI.color.faint.b, 1.0, UI.font.small)
    else
        self:drawText(UI.fit(UI.font.body, m.username, budget), tx,
            y + math.floor((h - UI.fh(UI.font.body)) / 2),
            nameCol.r, nameCol.g, nameCol.b, 1.0, UI.font.body)
    end
    return y + h
end

function LasciviousFactionsSystemPanel:onMemberRowClicked(row)
    self.selectedMember = row
    if row.isInvite then
        -- Invite rows: only revoke applies. Repurpose the kick button as "Revoke".
        if self.assignBtn then
            self.assignBtn:setEnable(false)
            self.assignBtn.tooltip = FF.tr("Invites can only be revoked")
        end
        if self.kickBtn then
            self.kickBtn.title = FF.tr("Revoke")
            self.kickBtn:setEnable(self.canManageMembers)
            self.kickBtn.tooltip = nil
        end
        if self.transferBtn then
            self.transferBtn:setEnable(false)
            self.transferBtn.tooltip = FF.tr("Select a member first")
        end
        return
    end
    local isOwnerRow = row.isOwner
    local isSelfRow = (row.username == getPlayer():getUsername())
    -- Assign works on any non-owner row (including yourself); kick excludes self.
    if self.assignBtn then
        local en = self.canManageMembers and not isOwnerRow
        self.assignBtn:setEnable(en)
        self.assignBtn.tooltip = en and nil or FF.tr(isOwnerRow
            and "The owner's role can't be changed" or "Select a member first")
    end
    if self.kickBtn then
        self.kickBtn.title = FF.tr("Kick")
        local en = self.canManageMembers and not isOwnerRow and not isSelfRow
        self.kickBtn:setEnable(en)
        self.kickBtn.tooltip = en and nil or FF.tr((isOwnerRow or isSelfRow)
            and "You can't kick this member" or "Select a member first")
    end
    if self.transferBtn then
        -- The owner's own row already has isOwnerRow == true, so this alone excludes self.
        local en = not isOwnerRow
        self.transferBtn:setEnable(en)
        self.transferBtn.tooltip = en and nil or FF.tr("Select a member first")
    end
end

-- Open a context menu listing every (non-owner) role of the faction; picking one
-- assigns it to the selected member via the existing setMemberRole intent.
function LasciviousFactionsSystemPanel:onAssignRoleClick(button)
    if not self.selectedMember then return end
    local _, faction = FF.getFactionOfPlayer(getPlayer():getUsername())
    if not faction then return end
    local target = self.selectedMember.username
    local roleNames = {}
    for rn in pairs(faction.roles or {}) do
        if rn ~= "owner" then table.insert(roleNames, rn) end
    end
    table.sort(roleNames)
    local menu = ISContextMenu.get(0, getMouseX(), getMouseY())
    for _, rn in ipairs(roleNames) do
        menu:addOption(FF.tr(rn), self, LasciviousFactionsSystemPanel.onAssignRolePick, target, rn)
    end
    menu:setAlwaysOnTop(true)
    menu:bringToTop()
end

-- ISContextMenu invokes onclick(target, param1, param2); here target=self(panel),
-- param1=member username, param2=role name.
function LasciviousFactionsSystemPanel:onAssignRolePick(username, roleName)
    send("setMemberRole", { username = username, role = roleName })
end

function LasciviousFactionsSystemPanel:onKickClick(button)
    if not self.selectedMember then return end
    local target = self.selectedMember.username
    -- The same button revokes a pending invite (no confirm needed for that).
    if self.selectedMember.isInvite then
        send("revokeInvite", { username = target })
        return
    end
    -- ISModalDialog param1 rides through to onclick's 3rd arg (ISModalDialog.lua:
    -- 58-64), so the kicked username travels there rather than on a made-up field.
    local modal = ISModalDialog:new(0, 0, 320, 130,
        FF.text("UI_LFS_KickMemberConfirm", "Kick %s from the faction?", target),
        true, self, LasciviousFactionsSystemPanel.onKickConfirm, nil, target)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end

-- Vanilla-style connected-player picker. The scoreboard gives the complete online
-- roster (including distant players); LFS filters out everyone who already belongs to
-- any LFS faction before presenting the list.
FactionInvitePlayerDialog = ISCollapsableWindow:derive("LFSFactionInvitePlayerDialog")
FactionInvitePlayerDialog.instance = nil

function FactionInvitePlayerDialog:new()
    local w, h = 430, 390
    local o = ISCollapsableWindow:new(
        math.floor((getCore():getScreenWidth() - w) / 2),
        math.floor((getCore():getScreenHeight() - h) / 2), w, h)
    setmetatable(o, self); self.__index = self
    o.title = FF.text("UI_LFS_InviteDialogTitle", "Invite player")
    o.resizable = false
    o.moveWithMouse = true
    o.scoreboard = nil
    FactionInvitePlayerDialog.instance = o
    return o
end

function FactionInvitePlayerDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad, th = UI.pad, self:titleBarHeight()
    local bh = UI.rowH(UI.font.body)
    local label = ISLabel:new(pad, th + 10, UI.fh(UI.font.body),
        FF.text("UI_LFS_EligibleOnlinePlayers", "Connected players without a faction"),
        UI.color.text.r, UI.color.text.g, UI.color.text.b, 1, UI.font.body, true)
    label:initialise(); self:addChild(label)

    local ly = th + 10 + UI.lineH(UI.font.body) + 6
    self.playerList = ISScrollingListBox:new(pad, ly, self:getWidth() - pad * 2,
        self:getHeight() - ly - bh - pad * 2)
    self.playerList:initialise(); self.playerList:instantiate()
    self.playerList.itemheight = UI.rowH(UI.font.body)
    self.playerList.font = UI.font.body
    self.playerList.drawBorder = true
    self.playerList.borderColor = UI.color.border
    self.playerList.backgroundColor = UI.color.panel
    self.playerList.doDrawItem = FactionInvitePlayerDialog.drawPlayer
    self:addChild(self.playerList)

    self.emptyLabel = ISLabel:new(pad + 10, ly + 10, UI.fh(UI.font.small),
        FF.text("UI_LFS_NoEligibleOnlinePlayers", "No player is currently available to invite."),
        UI.color.dim.r, UI.color.dim.g, UI.color.dim.b, 1, UI.font.small, true)
    self.emptyLabel:initialise(); self:addChild(self.emptyLabel)

    local by = self.playerList:getBottom() + pad
    local bw = math.floor((self:getWidth() - pad * 2 - 10) / 2)
    local cancel = FFButton:new(pad, by, bw, bh,
        FF.text("UI_LFS_CancelAction", "Cancel"), self,
        FactionInvitePlayerDialog.onCancel, "ghost")
    cancel:initialise(); cancel:instantiate(); self:addChild(cancel)
    self.inviteButton = FFButton:new(pad + bw + 10, by, bw, bh,
        FF.text("UI_LFS_InviteAction", "Invite"), self,
        FactionInvitePlayerDialog.onInvite, "primary", "ic_invite")
    self.inviteButton.disabledNeutral = true
    self.inviteButton:initialise(); self.inviteButton:instantiate()
    self.inviteButton:setEnable(false)
    self:addChild(self.inviteButton)

    if scoreboardUpdate then scoreboardUpdate() end
end

function FactionInvitePlayerDialog:populateList()
    if not self.playerList then return end
    self.playerList:clear()
    local board = self.scoreboard
    local me = getPlayer() and getPlayer():getUsername()
    if board and board.usernames then
        for i = 1, board.usernames:size() do
            local username = board.usernames:get(i - 1)
            local displayName = board.displayNames and board.displayNames:get(i - 1) or username
            if username ~= me and not FF.getFactionOfPlayer(username) then
                self.playerList:addItem(displayName, {
                    username = username,
                    displayName = displayName,
                })
            end
        end
    end
    self.playerList.selected = 0
    self.emptyLabel:setVisible(#self.playerList.items == 0)
    self.inviteButton:setEnable(false)
end

function FactionInvitePlayerDialog.drawPlayer(self, y, item, alt)
    local h, w = self.itemheight, self:getWidth()
    local selected = self.selected == item.index
    if selected then
        self:drawRect(0, y, w, h, 0.20, UI.color.accent.r, UI.color.accent.g, UI.color.accent.b)
        self:drawRect(0, y, 3, h, 1, UI.color.accent.r, UI.color.accent.g, UI.color.accent.b)
    elseif self.mouseoverselected == item.index and self:isMouseOver() then
        self:drawRect(0, y, w, h, 1, UI.color.panel2.r, UI.color.panel2.g, UI.color.panel2.b)
    end
    local cy = y + math.floor((h - UI.fh(UI.font.body)) / 2)
    self:drawText(UI.fit(UI.font.body, item.item.displayName, math.floor(w * 0.60)),
        10, cy, UI.color.text.r, UI.color.text.g, UI.color.text.b, 1, UI.font.body)
    if item.item.displayName ~= item.item.username then
        self:drawTextRight(item.item.username, w - 10, cy,
            UI.color.dim.r, UI.color.dim.g, UI.color.dim.b, 1, UI.font.small)
    end
    return y + h
end

function FactionInvitePlayerDialog:prerender()
    ISCollapsableWindow.prerender(self)
    local selected = self.playerList and self.playerList.selected or 0
    self.inviteButton:setEnable(selected > 0 and self.playerList.items[selected] ~= nil)
end

function FactionInvitePlayerDialog:onInvite()
    local i = self.playerList and self.playerList.selected or 0
    local row = i > 0 and self.playerList.items[i] or nil
    if not (row and row.item and row.item.username) then return end
    send("invite", { username = row.item.username })
    self:close()
end

function FactionInvitePlayerDialog:onCancel()
    self:close()
end

function FactionInvitePlayerDialog:close()
    if FactionInvitePlayerDialog.instance == self then FactionInvitePlayerDialog.instance = nil end
    self:setVisible(false)
    self:removeFromUIManager()
end

function FactionInvitePlayerDialog.OnScoreboardUpdate(usernames, displayNames, steamIDs)
    local dlg = FactionInvitePlayerDialog.instance
    if not dlg then return end
    dlg.scoreboard = { usernames = usernames, displayNames = displayNames, steamIDs = steamIDs }
    dlg:populateList()
end

function FactionInvitePlayerDialog.OnMiniScoreboardUpdate()
    if FactionInvitePlayerDialog.instance and scoreboardUpdate then scoreboardUpdate() end
end

if FF._panelScoreboardHook then Events.OnScoreboardUpdate.Remove(FF._panelScoreboardHook) end
if FF._panelMiniScoreboardHook then Events.OnMiniScoreboardUpdate.Remove(FF._panelMiniScoreboardHook) end
FF._panelScoreboardHook = FactionInvitePlayerDialog.OnScoreboardUpdate
FF._panelMiniScoreboardHook = FactionInvitePlayerDialog.OnMiniScoreboardUpdate
Events.OnScoreboardUpdate.Add(FF._panelScoreboardHook)
Events.OnMiniScoreboardUpdate.Add(FF._panelMiniScoreboardHook)

function LasciviousFactionsSystemPanel:onInviteClick(button)
    if FactionInvitePlayerDialog.instance then FactionInvitePlayerDialog.instance:close() end
    local dlg = FactionInvitePlayerDialog:new()
    dlg:initialise(); dlg:instantiate(); dlg:addToUIManager()
    dlg:setAlwaysOnTop(true); dlg:bringToTop()
end

function LasciviousFactionsSystemPanel:onKickConfirm(button, targetUsername)
    if button.internal == "YES" then
        send("kickMember", { username = targetUsername })
    end
end

function LasciviousFactionsSystemPanel:onTransferClick(button)
    if not self.selectedMember or self.selectedMember.isInvite then return end
    local target = self.selectedMember.username
    -- ISModalDialog param1 rides through to onclick's 3rd arg, same idiom as onKickClick.
    local modal = ISModalDialog:new(0, 0, 320, 150,
        FF.text("UI_LFS_TransferOwnerConfirm",
            "Transfer ownership to %s? You will become a regular member.", target),
        true, self, LasciviousFactionsSystemPanel.onTransferConfirm, nil, target)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end

function LasciviousFactionsSystemPanel:onTransferConfirm(button, targetUsername)
    if button.internal == "YES" then
        send("transferOwnership", { username = targetUsername })
    end
end

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------
local ROLE_PERM_LABELS = {
    claim         = "Claim & unclaim land",
    setRespawn    = "Set respawn point",
    build         = "Build in claims",
    move          = "Move / pick up items",
    manageMembers = "Manage members",
    startRaid     = "Declare raids",
    manageTribute = FF.text("UI_LFS_PermManageTribute", "Gerenciar tributos"),
    protectVehicles = FF.text("UI_LFS_PermProtectVehicles", "Proteger veículos"),
}

-- The Members tab's roles side pane. Roles are picked from a wrapping row of
-- chips rather than the old full-height list (the column is ~280px wide), then
-- the selected role's permissions and the owner's add/rename/delete controls
-- follow beneath -- all inside a scroll pane, since a faction with many custom
-- roles and eight permissions can outrun the column.
function LasciviousFactionsSystemPanel:buildRolesPane(x, y, w, h, faction, username)
    FF.ensureRoles(faction)
    self.rolesFactionName = self.membersFactionName
    self.roleNameEntry, self.roleRenameEntry = nil, nil
    local isOwner = (faction.owner == username)

    local card = FFCard:new(x, y, w, h)
    card:initialise(); card:instantiate(); self.content:addChild(card)

    local scroll = ISPanel:new(1, 1, w - 2, h - 2)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    card:addChild(scroll)
    self.activeScroll = scroll

    local pad = 12
    local colW = w - 2 - pad - 18   -- minus the scrollbar gutter
    local cy = 12

    local roleNames = {}
    for rn in pairs(faction.roles) do table.insert(roleNames, rn) end
    table.sort(roleNames)
    if not self.selectedRole or not faction.roles[self.selectedRole] then
        self.selectedRole = roleNames[1]
    end

    cardText(scroll, pad, cy, FF.text("UI_LFS_DynamicRole", "ROLE: %s",
        FF.tr(tostring(self.selectedRole or "-"))),
        UI.color.accent, UI.font.small)
    cy = cy + UI.fh(UI.font.small) + 6

    -- Role chips (wrapping). Each is a real button, so it gets the toolkit's
    -- hover/press feedback for free.
    local bx = pad
    local chipH = UI.rowH(UI.font.small)
    for _, rn in ipairs(roleNames) do
        local bw = UI.tw(UI.font.small, rn) + 22
        if bx > pad and bx + bw > pad + colW then bx = pad; cy = cy + chipH + 4 end
        local chip = FFButton:new(bx, cy, bw, chipH, rn, self, LasciviousFactionsSystemPanel.onRoleChipClick,
            (rn == self.selectedRole) and "primary" or "ghost")
        chip.font = UI.font.small
        chip.roleName = rn
        chip:initialise(); chip:instantiate(); scroll:addChild(chip)
        bx = bx + bw + 6
    end
    cy = cy + chipH + 8

    if not isOwner then
        cardText(scroll, pad, cy, "Only the owner can edit roles.", UI.color.faint, UI.font.small)
        cy = cy + UI.fh(UI.font.small) + 8
    end

    local role = self.selectedRole and faction.roles[self.selectedRole]
    if role then
        for _, perm in ipairs(FF.PERMISSIONS) do
            local onClick = isOwner and LasciviousFactionsSystemPanel.onRolePermToggle or nil
            local row = RolePermRow:new(pad, cy, colW, nil, ROLE_PERM_LABELS[perm] or perm,
                role[perm] == true, self, onClick)
            row:initialise(); row:instantiate()
            row.perm = perm
            row.roleName = self.selectedRole
            scroll:addChild(row)
            cy = cy + row:getHeight() + 2
        end
        cy = cy + 6
    end

    if isOwner then
        local RH = UI.rowH(UI.font.body)
        local addW = math.max(60, UI.buttonWidth("Add", false, RH))
        self.roleNameEntry = passWheel(ISTextEntryBox:new("", pad, cy, colW - addW - 6, RH))
        self.roleNameEntry:initialise(); self.roleNameEntry:instantiate()
        self.roleNameEntry.target = self
        scroll:addChild(self.roleNameEntry)
        local addBtn = FFButton:new(pad + colW - addW, cy, addW, RH, "Add", self, LasciviousFactionsSystemPanel.onAddRoleClick, "primary")
        addBtn:initialise(); addBtn:instantiate(); scroll:addChild(addBtn)
        cy = cy + RH + 8

        -- "member" is the reserved fallback role: it can't be renamed or deleted.
        if self.selectedRole and self.selectedRole ~= "member" then
            local renW = math.max(70, UI.buttonWidth("Rename", false, RH))
            self.roleRenameEntry = passWheel(ISTextEntryBox:new(self.selectedRole, pad, cy, colW - renW - 6, RH))
            self.roleRenameEntry:initialise(); self.roleRenameEntry:instantiate()
            self.roleRenameEntry.target = self
            scroll:addChild(self.roleRenameEntry)
            local renameBtn = FFButton:new(pad + colW - renW, cy, renW, RH, "Rename", self, LasciviousFactionsSystemPanel.onRenameRoleClick, "ghost")
            renameBtn:initialise(); renameBtn:instantiate(); scroll:addChild(renameBtn)
            cy = cy + RH + 6

            local delBtn = FFButton:new(pad, cy, colW, RH, "Delete role", self, LasciviousFactionsSystemPanel.onDeleteRoleClick, "danger", "ic_kick")
            delBtn:initialise(); delBtn:instantiate(); scroll:addChild(delBtn)
            cy = cy + RH + 6
        end
    end

    scroll:setScrollHeight(cy + 8)
end

function LasciviousFactionsSystemPanel:onRoleChipClick(button)
    if button and button.roleName then
        self.selectedRole = button.roleName
        self:showSection("members")   -- rebuild the pane for the new selection
    end
end

function LasciviousFactionsSystemPanel:onRolePermToggle(button)
    if not (button and button.roleName and button.perm) then return end
    local newValue = not button.on
    -- Optimistic flip: previously the checkbox only ever changed after the pane
    -- was rebuilt (switching roles away and back, or now also the live-refresh in
    -- refreshActiveSection), which read as "nothing happened" on click. This
    -- updates the widget immediately; the server confirms (or corrects, if the
    -- request is ever rejected) shortly after via the normal sync -> refresh path.
    button.on = newValue
    send("setRolePermission", { name = button.roleName, perm = button.perm, value = newValue })
end

function LasciviousFactionsSystemPanel:onAddRoleClick(button)
    if not self.roleNameEntry then return end
    local text = self.roleNameEntry:getInternalText()
    if text and text ~= "" then
        send("createRole", { name = text })
        self.roleNameEntry:setText("")
    end
end

function LasciviousFactionsSystemPanel:onRenameRoleClick(button)
    if not (self.roleRenameEntry and self.selectedRole) then return end
    local newName = self.roleRenameEntry:getInternalText()
    if newName and newName ~= "" and newName ~= self.selectedRole then
        send("renameRole", { name = self.selectedRole, newName = newName })
        self.selectedRole = newName   -- follow the rename so the pane stays on it
    end
end

function LasciviousFactionsSystemPanel:onDeleteRoleClick(button)
    if not self.selectedRole then return end
    local modal = ISModalDialog:new(0, 0, 340, 130,
        FF.text("UI_LFS_DeleteRoleConfirm",
            "Delete role '%s'? Its members become 'member'.", self.selectedRole),
        true, self, LasciviousFactionsSystemPanel.onDeleteRoleConfirm, nil, self.selectedRole)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end

function LasciviousFactionsSystemPanel:onDeleteRoleConfirm(button, roleName)
    if button.internal == "YES" then
        send("deleteRole", { name = roleName })
        self.selectedRole = nil   -- fall back to first role on rebuild
    end
end

-- ---------------------------------------------------------------------------
-- Relations (ally / enemy)
-- ---------------------------------------------------------------------------
local REL_LABEL = { ally = "ALLY", enemy = "ENEMY", incoming = "WANTS ALLY", outgoing = "REQUEST SENT", pact = "PACT" }
local function relColor(status)
    if status == "ally" then return UI.color.good
    elseif status == "enemy" then return UI.color.bad
    elseif status == "incoming" then return UI.color.accent
    elseif status == "outgoing" then return UI.color.warn
    elseif status == "pact" then return UI.color.good
    else return UI.color.dim end
end

-- This faction's status toward `otherName`: ally/enemy/incoming/outgoing/neutral.
local function relationStatus(name, faction, otherName)
    if FF.areAllied(name, otherName) then return "ally" end
    if faction.relations and faction.relations[otherName] == "enemy" then return "enemy" end
    if faction.allyRequests and faction.allyRequests[otherName] then return "incoming" end
    local other = FF.getFaction(otherName)
    if other and other.allyRequests and other.allyRequests[name] then return "outgoing" end
    return "neutral"
end

function LasciviousFactionsSystemPanel:populateRelations()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end

    local x = UI.pad
    local innerW = self.content:getWidth() - 2 * UI.pad
    local y = self:addHeader(name, faction, username)

    self.relationsIsOwner = (faction.owner == username)
    self.relationsFactionName = name

    local others = {}
    for other in pairs(FF.getData().factions or {}) do
        if other ~= name then table.insert(others, other) end
    end
    table.sort(others)

    if #others == 0 then
        local note = Notice:new(x, y, innerW, "No other factions exist yet.", UI.color.dim, nil)
        note:initialise(); self.content:addChild(note)
        return
    end

    if not self.relationsIsOwner then
        local note = Notice:new(x, y, innerW, "Only the faction owner can change relationships.", UI.color.dim, nil)
        note:initialise(); self.content:addChild(note)
        y = y + note:getHeight() + 10
    end

    self.relationList = ISScrollingListBox:new(x, y, innerW, self.content:getHeight() - y - UI.pad)
    self.relationList.backgroundColor = UI.color.panel
    self.relationList:initialise(); self.relationList:instantiate()
    self.relationList.itemheight = UI.rowH(UI.font.body)   -- one line of text per row
    self.relationList.font = UI.font.body
    self.relationList.drawBorder = true
    self.relationList.borderColor = UI.color.border
    self.relationList.doDrawItem = LasciviousFactionsSystemPanel.drawRelationRow
    self.relationList.target = self
    -- Open the context menu on mouse-UP, not mouse-down: opening it on the press
    -- means the same click's release lands on the freshly-opened menu and instantly
    -- selects the option under the cursor. (Base onMouseDown still sets .selected.)
    self.relationList.onMouseUp = function(lst, x, y)
        ISScrollingListBox.onMouseUp(lst, x, y)   -- keep scrollbar behaviour
        local row = lst:rowAt(x, y)
        if not row or row < 1 or row > #lst.items then return end
        lst.selected = row
        local panel = lst.target
        if panel then
            panel:openRelationMenu(lst.items[row].item, lst:getAbsoluteX() + x, lst:getAbsoluteY() + y)
        end
    end
    local opts = FF.getOptions()
    local nowMsClient = getTimestamp() * 1000
    for _, other in ipairs(others) do
        local item = { name = other, status = relationStatus(name, faction, other) }
        if opts.warsEnabled then
            local war = FF.warBetween(name, other)
            if war then
                item.status = "war"
                item.warMine = (war.score and war.score[name]) or 0
                item.warTheirs = (war.score and war.score[other]) or 0
            else
                local cf = FF.ceasefireLeft(name, other, nowMsClient)
                if cf > 0 then item.ceasefire = cf end
            end
        end
        if opts.pactsEnabled then
            item.pactActive = FF.pactActive(name, other, nowMsClient)
            item.pactIncoming = (faction.pactRequests and faction.pactRequests[other]) and true or false
            local of = FF.getFaction(other)
            item.pactOutgoing = (of and of.pactRequests and of.pactRequests[name]) and true or false
            if item.pactActive and item.status ~= "war" then item.status = "pact" end
        end
        self.relationList:addItem(other, item)
    end
    self.content:addChild(self.relationList)
end

function LasciviousFactionsSystemPanel.drawRelationRow(self, y, item, alt)
    local h, w = self.itemheight, self:getWidth()
    local hover = (self.mouseoverselected == item.index) and self:isMouseOver()
    if hover then
        self:drawRect(0, y, w, h, 1.0, UI.color.panel2.r, UI.color.panel2.g, UI.color.panel2.b)
    end
    local cy = y + math.floor((h - UI.fh(UI.font.body)) / 2)
    self:drawText(item.item.name, 10, cy, UI.color.text.r, UI.color.text.g, UI.color.text.b, 1.0, UI.font.body)
    local status = item.item.status
    if status == "war" then
        local c = UI.color.bad
        self:drawTextRight(FF.text("UI_LFS_RelationAtWar", "AT WAR  %d-%d",
            item.item.warMine or 0, item.item.warTheirs or 0),
            w - 10, cy, c.r, c.g, c.b, 1.0, UI.font.small)
    elseif item.item.ceasefire then
        local c = UI.color.warn
        self:drawTextRight(FF.text("UI_LFS_RelationCeasefire", "CEASEFIRE %dh",
            math.ceil(item.item.ceasefire / 3600)),
            w - 10, cy, c.r, c.g, c.b, 1.0, UI.font.small)
    elseif status and status ~= "neutral" then
        local col = relColor(status)
        self:drawTextRight(FF.tr(REL_LABEL[status] or ""), w - 10, cy,
            col.r, col.g, col.b, 1.0, UI.font.small)
    elseif item.item.pactIncoming then
        local c = UI.color.accent
        self:drawTextRight(FF.tr("PACT OFFER"), w - 10, cy, c.r, c.g, c.b, 1.0, UI.font.small)
    elseif item.item.pactOutgoing then
        local c = UI.color.warn
        self:drawTextRight(FF.tr("PACT SENT"), w - 10, cy, c.r, c.g, c.b, 1.0, UI.font.small)
    end
    return y + h
end

-- One-line human summary of a pact contract (a stored pending proposal, or an active
-- pact record). Handles the legacy `true` proposal (defaults) and the {terms=...} shape.
local function pactContractSummary(c)
    if type(c) ~= "table" then return FF.tr("Indefinite, no extra terms.") end
    local dur = (c.durationDays and c.durationDays > 0)
        and FF.text("UI_LFS_PactDays", "%d days", c.durationDays) or FF.tr("indefinite")
    local shares = {}
    local t = (type(c.terms) == "table") and c.terms or c
    if t.shareMap then shares[#shares + 1] = FF.tr("map") end
    if t.shareLocations then shares[#shares + 1] = FF.tr("locations") end
    local terms = #shares > 0 and FF.text("UI_LFS_SharesTerms",
        "  |  shares %s", table.concat(shares, "+")) or ""
    return FF.text("UI_LFS_PactDuration", "Duration: %s%s", dur, terms)
end

-- Owner clicks a faction row -> a context menu with the valid actions for that
-- relationship state; each option fires the matching intent (server re-checks).
function LasciviousFactionsSystemPanel:openRelationMenu(item, sx, sy)
    if not (self.relationsIsOwner and item and item.name) then return end
    local other = item.name
    local status = item.status
    local opts = FF.getOptions()
    local warsOn = opts.warsEnabled
    -- With wars enabled, the hostile action escalates to a formal war instead of the
    -- cosmetic enemy flag. Suppressed while a pact protects the target (server rejects).
    local function addHostileOption(menu)
        if item.pactActive then return end
        if warsOn then
            menu:addOption(FF.tr("Declare war"), self, LasciviousFactionsSystemPanel.onRelDeclareWar, other)
        else
            menu:addOption(FF.tr("Declare enemy"), self, LasciviousFactionsSystemPanel.onRelSetEnemy, other)
        end
    end
    -- Pact actions vary with the pact state carried on the row.
    local function addPactOption(menu)
        if not opts.pactsEnabled then return end
        if item.pactActive then
            menu:addOption(FF.tr("Break pact"), self, LasciviousFactionsSystemPanel.onRelBreakPact, other)
        elseif item.pactIncoming then
            menu:addOption(FF.tr("Accept pact"), self, LasciviousFactionsSystemPanel.onRelAcceptPact, other)
            menu:addOption(FF.tr("Decline pact"), self, LasciviousFactionsSystemPanel.onRelDeclinePact, other)
        elseif item.pactOutgoing then
            menu:addOption(FF.tr("Cancel pact offer"), self, LasciviousFactionsSystemPanel.onRelCancelPact, other)
        elseif status ~= "enemy" and status ~= "war" then
            menu:addOption(FF.tr("Propose pact"), self, LasciviousFactionsSystemPanel.onRelProposePact, other)
        end
    end
    local menu = ISContextMenu.get(0, sx, sy)
    if status == "war" then
        menu:addOption(FF.tr("Surrender war"), self, LasciviousFactionsSystemPanel.onRelSurrenderWar, other)
    elseif status == "pact" then
        menu:addOption(FF.tr("Break pact"), self, LasciviousFactionsSystemPanel.onRelBreakPact, other)
        menu:addOption(FF.tr("Request alliance"), self, LasciviousFactionsSystemPanel.onRelReqAlly, other)
    elseif status == "ally" then
        menu:addOption(FF.tr("Break alliance"), self, LasciviousFactionsSystemPanel.onRelBreakAlly, other)
        addPactOption(menu)   -- allies may also sign a formal non-aggression pact
    elseif status == "enemy" then
        menu:addOption(FF.tr("Clear (set neutral)"), self, LasciviousFactionsSystemPanel.onRelClearEnemy, other)
        addHostileOption(menu)
    elseif status == "incoming" then
        menu:addOption(FF.tr("Accept alliance"), self, LasciviousFactionsSystemPanel.onRelAcceptAlly, other)
        menu:addOption(FF.tr("Decline alliance"), self, LasciviousFactionsSystemPanel.onRelDeclineAlly, other)
        addHostileOption(menu)
        addPactOption(menu)
    elseif status == "outgoing" then
        menu:addOption(FF.tr("Cancel request"), self, LasciviousFactionsSystemPanel.onRelCancel, other)
        addHostileOption(menu)
        addPactOption(menu)
    else -- neutral
        menu:addOption(FF.tr("Request alliance"), self, LasciviousFactionsSystemPanel.onRelReqAlly, other)
        addHostileOption(menu)
        addPactOption(menu)
    end
    -- Coalition: join an ally's war against `other`, or leave one we joined. Only when
    -- `other` is a principal of an active war and we're allied to the other side.
    local myName = self.relationsFactionName
    if warsOn and myName then
        for _, war in pairs(FF.getData().wars or {}) do
            local side = (war.a == other and "a") or (war.b == other and "b") or nil
            if side then
                local allyPrincipal = (side == "a") and war.b or war.a
                local myInWar = war.a == myName or war.b == myName or (war.coalition and war.coalition[myName])
                if war.coalition and war.coalition[myName] then
                    menu:addOption(FF.tr("Leave the war"), self, LasciviousFactionsSystemPanel.onRelLeaveWar, other)
                elseif not myInWar and FF.areAllied(myName, allyPrincipal) then
                    menu:addOption(FF.text("UI_LFS_JoinWarVs", "Join war vs %s", tostring(other)),
                        self, LasciviousFactionsSystemPanel.onRelJoinWar, other)
                end
                break
            end
        end
    end
    -- The dashboard window re-tops itself on the click, so force the menu above it.
    menu:setAlwaysOnTop(true)
    menu:bringToTop()
end

function LasciviousFactionsSystemPanel:onRelReqAlly(other) send("allyRequest", { target = other }) end
function LasciviousFactionsSystemPanel:onRelProposePact(other)
    local d = FactionPactDialog:new(other)
    d:initialise(); d:instantiate(); d:addToUIManager()
    d:setAlwaysOnTop(true); d:bringToTop()
end
function LasciviousFactionsSystemPanel:onRelAcceptPact(other)
    -- Show the offered contract (read from the synced pending proposal) before accepting.
    local _, faction = FF.getFactionOfPlayer(getPlayer():getUsername())
    local c = faction and faction.pactRequests and faction.pactRequests[other]
    local modal = ISModalDialog:new(0, 0, 440, 170,
        FF.text("UI_LFS_AcceptPactConfirm",
            "Accept non-aggression pact from %s?\n\n%s", tostring(other), pactContractSummary(c)),
        true, self, LasciviousFactionsSystemPanel.onRelAcceptPactConfirm, nil, other)
    modal:initialise(); modal:addToUIManager(); modal:setAlwaysOnTop(true); modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end
function LasciviousFactionsSystemPanel:onRelAcceptPactConfirm(button, other)
    if button.internal == "YES" then send("respondPact", { other = other, accept = true }) end
end
function LasciviousFactionsSystemPanel:onRelDeclinePact(other) send("respondPact", { other = other, accept = false }) end
function LasciviousFactionsSystemPanel:onRelCancelPact(other) send("cancelPact", { target = other }) end
function LasciviousFactionsSystemPanel:onRelBreakPact(other)
    -- Surface the agreed terms before the owner commits -- these are the contract
    -- terms they signed up to.
    local myName = self.relationsFactionName
    local p = myName and FF.pactBetween(myName, other)
    local msg = FF.text("UI_LFS_BreakPactConfirm",
        "Break your non-aggression pact with %s?", tostring(other))
    if p then
        msg = msg .. "\n\n" .. pactContractSummary(p)
    end
    local modal = ISModalDialog:new(0, 0, 460, 190, msg, true, self,
        LasciviousFactionsSystemPanel.onRelBreakPactConfirm, nil, other)
    modal:initialise(); modal:addToUIManager(); modal:setAlwaysOnTop(true); modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end
function LasciviousFactionsSystemPanel:onRelBreakPactConfirm(button, other)
    if button.internal == "YES" then send("breakPact", { target = other }) end
end
function LasciviousFactionsSystemPanel:onRelJoinWar(other) send("joinWar", { target = other }) end
function LasciviousFactionsSystemPanel:onRelLeaveWar(other) send("leaveWar", { target = other }) end
function LasciviousFactionsSystemPanel:onRelDeclareWar(other) send("declareWar", { target = other }) end
function LasciviousFactionsSystemPanel:onRelSurrenderWar(other)
    local modal = ISModalDialog:new(0, 0, 360, 130,
        FF.text("UI_LFS_SurrenderWarConfirm", "Surrender the war with %s?", tostring(other)),
        true, self, LasciviousFactionsSystemPanel.onSurrenderWarConfirm, nil, other)
    modal:initialise(); modal:addToUIManager(); modal:setAlwaysOnTop(true); modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end
function LasciviousFactionsSystemPanel:onRelCancel(other) send("allyCancel", { target = other }) end
function LasciviousFactionsSystemPanel:onRelAcceptAlly(other) send("allyRespond", { other = other, accept = true }) end
function LasciviousFactionsSystemPanel:onRelDeclineAlly(other) send("allyRespond", { other = other, accept = false }) end
function LasciviousFactionsSystemPanel:onRelBreakAlly(other)
    -- ISModalDialog param1 rides through to onclick's 3rd arg, carrying the ally name.
    local modal = ISModalDialog:new(0, 0, 340, 130,
        FF.text("UI_LFS_BreakAllianceConfirm", "Break your alliance with %s?", tostring(other)),
        true, self, LasciviousFactionsSystemPanel.onRelBreakAllyConfirm, nil, other)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end
function LasciviousFactionsSystemPanel:onRelBreakAllyConfirm(button, other)
    if button.internal == "YES" then send("allyBreak", { other = other }) end
end
function LasciviousFactionsSystemPanel:onRelSetEnemy(other) send("setEnemy", { target = other, on = true }) end
function LasciviousFactionsSystemPanel:onRelClearEnemy(other) send("setEnemy", { target = other, on = false }) end

-- ---------------------------------------------------------------------------
-- Leaderboard (read-only ranking of every faction)
-- ---------------------------------------------------------------------------
-- Global view: ranks ALL factions by FF.factionScore (the live sum of every current
-- member's current-character zombie-kill + hours-survived totals). Data rides the replicated
-- registry, so no new sync path -- the list reflects whatever FF.getData() holds on
-- this client.
function LasciviousFactionsSystemPanel:populateLeaderboard()
    local username = getPlayer():getUsername()
    local myName = FF.getFactionOfPlayer(username)
    local x = UI.pad
    local innerW = self.content:getWidth() - 2 * UI.pad

    local y
    if myName then
        y = self:addHeader(myName, FF.getFaction(myName), username)
    elseif self.suppressHeader then
        y = self.sectionTop or 0
    else
        self:addLabel(x, 14, "Leaderboard", UI.color.text, UI.font.title)
        y = 14 + UI.fh(UI.font.title) + 10
    end
    self.leaderboardMyName = myName

    local opts = FF.getOptions()
    -- With seasons on, rank by score earned THIS season (baseline-adjusted) unless the
    -- viewer toggled the all-time view.
    local seasonMode = opts.seasonsEnabled and not self.leaderboardAllTime
    local ranked = {}
    for fname, faction in pairs(FF.getData().factions or {}) do
        table.insert(ranked, {
            name = fname,
            score = seasonMode and FF.seasonScore(faction, opts, fname) or FF.factionScore(faction, opts, fname),
            members = FF.memberCount(faction),
            tiles = FF.totalArea(faction.claims or {}),
            raidsWon = (faction.stats and faction.stats.raidsWon) or 0,
        })
    end
    -- Highest score first; ties broken by name for a stable order.
    table.sort(ranked, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)

    if #ranked == 0 then
        local note = Notice:new(x, y, innerW, "No factions exist yet.", UI.color.dim, nil)
        note:initialise(); self.content:addChild(note)
        return
    end

    -- Season header: which season, a Season/All-time toggle, and the hall of fame.
    if opts.seasonsEnabled then
        local season = FF.getData().season or {}
        local tglH = UI.rowH(UI.font.small)
        local hdr = ISLabel:new(x, y + math.floor((tglH - UI.fh(UI.font.body)) / 2), UI.fh(UI.font.body),
            FF.text("UI_LFS_SeasonRanking", "Season %d  --  %s ranking", season.number or 1,
                FF.tr(seasonMode and "this season" or "all-time")),
            UI.color.text.r, UI.color.text.g, UI.color.text.b, 1.0, UI.font.body, true)
        hdr:initialise(); self.content:addChild(hdr)
        local tglW = math.max(UI.buttonWidth("Show all-time", false, tglH), UI.buttonWidth("Show season", false, tglH))
        local tgl = FFButton:new(x + innerW - tglW, y, tglW, tglH,
            seasonMode and "Show all-time" or "Show season", self, LasciviousFactionsSystemPanel.onLeaderboardToggle, "ghost")
        tgl:initialise(); tgl:instantiate(); self.content:addChild(tgl)
        y = y + math.max(UI.lineH(UI.font.body), tglH) + 6

        local hist = season.history
        if hist and #hist > 0 then
            local shown = math.min(#hist, 5)
            local hCardH = UI.cardH(UI.cardTop() + shown * UI.lineH(UI.font.small))
            local hCard = FFCard:new(x, y, innerW, hCardH, "HALL OF FAME")
            hCard:initialise(); hCard:instantiate(); self.content:addChild(hCard)
            local hy = hCard:contentTop()
            for i = 1, shown do
                local e = hist[i]
                cardText(hCard, 12, hy, FF.text("UI_LFS_SeasonHistory",
                    "Season %s   %s   (%s pts)", tostring(e.number or "?"),
                    e.winner and tostring(e.winner) or FF.tr("no one"), tostring(e.score or 0)),
                    UI.color.accent)
                hy = hy + UI.lineH(UI.font.small)
            end
            y = y + hCardH + 10
        end
    end

    self.leaderboardList = ISScrollingListBox:new(x, y, innerW, self.content:getHeight() - y - UI.pad)
    self.leaderboardList.backgroundColor = UI.color.panel
    self.leaderboardList:initialise(); self.leaderboardList:instantiate()
    self.leaderboardList.itemheight = 5 + UI.lineH(UI.font.body) + UI.lineH(UI.font.small) + 4   -- two lines of text per row
    self.leaderboardList.font = UI.font.body
    self.leaderboardList.drawBorder = true
    self.leaderboardList.borderColor = UI.color.border
    self.leaderboardList.doDrawItem = LasciviousFactionsSystemPanel.drawLeaderboardRow
    self.leaderboardList.target = self
    for i, row in ipairs(ranked) do
        row.rank = i
        self.leaderboardList:addItem(row.name, row)
    end
    self.content:addChild(self.leaderboardList)
end

function LasciviousFactionsSystemPanel.drawLeaderboardRow(self, y, item, alt)
    local h, w = self.itemheight, self:getWidth()
    local row = item.item
    local isMine = self.target and self.target.leaderboardMyName == row.name

    -- Own faction row gets a faint accent wash; hover a slightly lighter panel.
    if isMine then
        local a = UI.color.accent
        self:drawRect(0, y, w, h, 0.16, a.r, a.g, a.b)
    end
    if (self.mouseoverselected == item.index) and self:isMouseOver() then
        self:drawRect(0, y, w, h, 1.0, UI.color.panel2.r, UI.color.panel2.g, UI.color.panel2.b)
    end

    local fc = UI.factionColor(row.name)
    local topY = y + 5
    local botY = y + 5 + UI.fh(UI.font.body) - 1

    -- Rank + faction name (name tinted with the faction accent).
    self:drawText(tostring(row.rank) .. ".", 8, topY,
        UI.color.dim.r, UI.color.dim.g, UI.color.dim.b, 1.0, UI.font.small)
    self:drawText(row.name, 34, topY, fc.r, fc.g, fc.b, 1.0, UI.font.body)

    -- Score, right-aligned and prominent.
    self:drawTextRight(tostring(math.floor(row.score)), w - 10, topY,
        UI.color.text.r, UI.color.text.g, UI.color.text.b, 1.0, UI.font.body)

    -- Compact stat detail line.
    local detail = FF.text("UI_LFS_LeaderboardDetail",
        "%d members  %d tiles  %d raids won", row.members, row.tiles, row.raidsWon)
    self:drawText(detail, 34, botY,
        UI.color.dim.r, UI.color.dim.g, UI.color.dim.b, 1.0, UI.font.small)

    return y + h
end

function LasciviousFactionsSystemPanel:onLeaderboardToggle(button)
    self.leaderboardAllTime = not self.leaderboardAllTime
    self:showSection("leaderboard")
end

-- ---------------------------------------------------------------------------
-- Settings (owner-only editing)
-- ---------------------------------------------------------------------------

-- Preset accent-colour palette (same S/V as the name-derived colours).
local SETTINGS_SWATCHES = {}
for i = 0, 9 do SETTINGS_SWATCHES[#SETTINGS_SWATCHES + 1] = UI.hsv(i / 10, 0.55, 0.85) end

local function colorsMatch(a, b)
    if not (a and b) then return false end
    local function eq(x, y) return math.abs(x - y) < 0.02 end
    return eq(a.r, b.r) and eq(a.g, b.g) and eq(a.b, b.b)
end

-- ---------------------------------------------------------------------------
-- Surrendering concedes the war outright (the opponent is declared the winner), so
-- confirm before conceding.
function LasciviousFactionsSystemPanel:onSurrenderWar(button)
    local opp = button and button.warOpponent
    if not opp then return end
    local modal = ISModalDialog:new(0, 0, 360, 130,
        FF.text("UI_LFS_SurrenderWarConfirm", "Surrender the war with %s?", tostring(opp)),
        true, self, LasciviousFactionsSystemPanel.onSurrenderWarConfirm, nil, opp)
    modal:initialise(); modal:addToUIManager(); modal:setAlwaysOnTop(true); modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end
function LasciviousFactionsSystemPanel:onSurrenderWarConfirm(button, opp)
    if button.internal == "YES" then send("surrenderWar", { target = opp }) end
end

function LasciviousFactionsSystemPanel:populateSettings()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end

    local x = UI.pad
    local innerW = self.content:getWidth() - 2 * UI.pad
    local y = self:addHeader(name, faction, username)
    local isOwner = (faction.owner == username)

    local pvpOn = faction.friendlyFire == true

    -- Read-only view for non-owners.
    if not isOwner then
        local card = FFCard:new(x, y, innerW, 0, "FACTION SETTINGS")
        card:initialise(); card:instantiate(); self.content:addChild(card)
        local ry = card:contentTop()
        ry = self:addStatRow(card, 12, ry, innerW - 24, "Tag", tostring(faction.tag or "-"), UI.color.accent)
        ry = self:addStatRow(card, 12, ry, innerW - 24, "Description",
            (faction.description ~= "" and faction.description) or "(none)", UI.color.dim)
        ry = self:addStatRow(card, 12, ry, innerW - 24, "PvP between members",
            pvpOn and "Allowed" or "Blocked", pvpOn and UI.color.bad or UI.color.good)
        ry = self:addStatRow(card, 12, ry, innerW - 24, "Allies can build/craft here",
            (faction.allowAllyBuild == true) and "Allowed" or "Blocked", UI.color.dim)
        ry = self:addStatRow(card, 12, ry, innerW - 24, "Allies can destroy/move here",
            (faction.allowAllyMove == true) and "Allowed" or "Blocked", UI.color.dim)
        y = y + card:setContentHeight(ry) + 10
        local note = Notice:new(x, y, innerW, "Only the faction owner can edit settings.", UI.color.dim, nil)
        note:initialise(); self.content:addChild(note)
        return
    end

    -- Owner: editable controls, grouped into titled cards to match the other tabs.
    -- (FFCard is a plain container; interactive children work -- the Roles tab nests
    -- RolePermRows the same way.)
    local function cardLabel(card, lx, ly, text, color, font)
        text = FF.tr(text)
        local col = color or UI.color.text
        font = font or UI.font.body
        local l = ISLabel:new(lx, ly, UI.fh(font), text, col.r, col.g, col.b, 1.0, font, true)
        l:initialise(); card:addChild(l)
    end

    -- The owner controls can be taller than the window, so host them in a scroll pane
    -- filling the content area below the header. Cards are laid out relative to it.
    local scroll = ISPanel:new(0, y, self.content:getWidth(), self.content:getHeight() - y)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    self.content:addChild(scroll)
    self.settingsScroll = scroll
    self.activeScroll = scroll
    local colX = UI.pad
    local colW = innerW - 16            -- leave room for the scrollbar on the right
    local rowY = UI.pad

    -- Identity: tag + description (these require the explicit Save button).
    local EH = UI.rowH(UI.font.body)
    local labelStep = UI.lineH(UI.font.small) + 2
    local idCard = FFCard:new(colX, rowY, colW, 0, "IDENTITY")
    idCard:initialise(); idCard:instantiate(); scroll:addChild(idCard)
    local iy = idCard:contentTop()
    cardLabel(idCard, 12, iy, "Description (shown when players enter your claim)"); iy = iy + labelStep
    self.settingsDescEntry = passWheel(ISTextEntryBox:new(tostring(faction.description or ""), 12, iy, colW - 24, EH))
    self.settingsDescEntry:initialise(); self.settingsDescEntry:instantiate()
    self.settingsDescEntry.target = self
    idCard:addChild(self.settingsDescEntry)
    iy = iy + EH + 8
    cardLabel(idCard, 12, iy, "Faction tag"); iy = iy + labelStep
    self.settingsTagEntry = passWheel(ISTextEntryBox:new(tostring(faction.tag or ""), 12, iy, 200, EH))
    self.settingsTagEntry:initialise(); self.settingsTagEntry:instantiate()
    self.settingsTagEntry.target = self
    idCard:addChild(self.settingsTagEntry)
    iy = iy + EH + 8
    cardLabel(idCard, 12, iy, "Message of the day (shown to members on login)"); iy = iy + labelStep
    self.settingsMotdEntry = passWheel(ISTextEntryBox:new(tostring(faction.motd or ""), 12, iy, colW - 24, EH))
    self.settingsMotdEntry:initialise(); self.settingsMotdEntry:instantiate()
    self.settingsMotdEntry.target = self
    idCard:addChild(self.settingsMotdEntry)
    iy = iy + EH + 8
    local saveW = math.max(100, UI.buttonWidth("Save", false, EH))
    local saveBtn = FFButton:new(colW - 12 - saveW, iy, saveW, EH, "Save", self, LasciviousFactionsSystemPanel.onSettingsSave, "primary")
    saveBtn:initialise(); saveBtn:instantiate(); idCard:addChild(saveBtn)
    rowY = rowY + idCard:setContentHeight(iy + EH) + 10

    -- Faction/territory colour swatches (Auto + preset hues), applied immediately.
    -- Swatches are decorative squares, so their SIZE stays literal; only the card
    -- around them follows the title font.
    local size, gap = 26, 6
    local acCard = FFCard:new(colX, rowY, colW, 0, "ACCENT COLOUR")
    acCard:initialise(); acCard:instantiate(); scroll:addChild(acCard)
    local swY = acCard:contentTop()
    local sx = 12
    local autoSel = (faction.color == nil)
    local auto = ColorSwatch:new(sx, swY, size, nil, autoSel, self, LasciviousFactionsSystemPanel.onColorSwatchClick)
    auto:initialise(); auto:instantiate(); acCard:addChild(auto)
    sx = sx + size + gap
    for _, col in ipairs(SETTINGS_SWATCHES) do
        local sel = colorsMatch(faction.color, col)
        local sw = ColorSwatch:new(sx, swY, size, col, sel, self, LasciviousFactionsSystemPanel.onColorSwatchClick)
        sw:initialise(); sw:instantiate(); acCard:addChild(sw)
        sx = sx + size + gap
    end
    rowY = rowY + acCard:setContentHeight(swY + size) + 10

    -- Faction tribute rate: owner-only (same gate as color/territory settings
    -- above), grouped right beneath them. The slider commits (sends
    -- setFactionTributeRate) on mouse-up, same "commit on interaction end" feel
    -- as the rest of this tab's immediate-apply controls.
    if faction.owner == username then
        local trCard = FFCard:new(colX, rowY, colW, 0, FF.text("UI_LFS_TributeRateCardTitle", "ALÍQUOTA DE TRIBUTO"))
        trCard:initialise(); trCard:instantiate(); scroll:addChild(trCard)
        local ty = trCard:contentTop()
        local desc = ISLabel:new(12, ty, UI.fh(UI.font.small),
            FF.text("UI_LFS_TributeRateDesc",
                "Porcentagem dos créditos ganhos pelos membros que vai para o tesouro da facção."),
            UI.color.dim.r, UI.color.dim.g, UI.color.dim.b, 1.0, UI.font.small, true)
        desc:initialise(); trCard:addChild(desc)
        ty = ty + UI.lineH(UI.font.small) + 10
        local sliderH = 20
        FF.ensureTribute(faction)
        local slider = TributeRateSlider:new(12, ty, colW - 24 - 46, sliderH, faction.tribute.ratePercent,
            LasciviousFactionsSystemPanel.onTributeRateCommit, self)
        slider:initialise(); slider:instantiate(); trCard:addChild(slider)
        self.tributeRateSlider = slider
        ty = ty + sliderH + 10
        rowY = rowY + trCard:setContentHeight(ty) + 10
    end

    -- Toggles apply immediately on click; reuse the Roles checkbox row.
    --
    -- These used to be one undifferentiated "OPTIONS" card of seven checkboxes, where
    -- "Invite-only" sat next to "Allies can destroy & move objects in our claims" as
    -- though they were the same kind of decision. They are now grouped by who each one
    -- is about -- your own members, or your allies -- so the list can be found in
    -- rather than read through.
    local ow = colW - 24
    local orH = UI.fh(UI.font.body) + 8 + 4   -- RolePermRow's own height plus the gap
    local function toggleCard(title, rows, footnote)
        local card = FFCard:new(colX, rowY, colW, 0, title)
        card:initialise(); card:instantiate(); scroll:addChild(card)
        local oy = card:contentTop()
        for _, r in ipairs(rows) do
            local row = RolePermRow:new(12, oy, ow, nil, r.label, r.on, self,
                LasciviousFactionsSystemPanel.onSettingToggle)
            row:initialise(); row:instantiate()
            row.settingKey = r.key
            card:addChild(row)
            oy = oy + orH
        end
        if footnote then
            oy = oy + 4
            cardLabel(card, 12, oy, footnote, UI.color.dim, UI.font.small)
            oy = oy + UI.fh(UI.font.small)
        end
        rowY = rowY + card:setContentHeight(oy) + 10
        return card
    end

    toggleCard("MEMBERSHIP", {
        { key = "friendlyFire", label = "Allow PvP between members", on = pvpOn },
    }, "Options apply immediately. Tag & description need the Save button.")

    toggleCard("CLAIM ACCESS FOR ALLIES", {
        { key = "shareMapWithAllies", label = "Share our claims with allies",
          on = faction.shareMapWithAllies ~= false },
        { key = "shareMemberLocations", label = "Share member locations with allies",
          on = faction.shareMemberLocations == true },
        { key = "allowAllyBuild", label = "Allies can build & craft in our claims",
          on = faction.allowAllyBuild == true },
        { key = "allowAllyMove", label = "Allies can destroy & move objects in our claims",
          on = faction.allowAllyMove == true },
    })

    -- Danger zone. Disbanding used to live as a button on the Overview tab's action
    -- row, one click away from "Manage claim" and with nothing around it to say how
    -- final it is. It belongs here, last, behind its own red-kickered card that says
    -- in words what it destroys.
    if faction.owner == username then
        local dzCard = FFCard:new(colX, rowY, colW, 0, "DANGER ZONE")
        dzCard.kickerColor = UI.color.bad
        dzCard:initialise(); dzCard:instantiate(); scroll:addChild(dzCard)
        local dy = dzCard:contentTop()
        local dbW = UI.buttonWidth("Disband faction", false, EH)
        local warnLines = wrapText(FF.tr(
            "Disbanding releases every claim your faction holds and removes all members. This cannot be undone."),
            UI.font.small, colW - 36 - dbW)
        local warnTop = dy
        for _, line in ipairs(warnLines) do
            cardLabel(dzCard, 12, dy, line, UI.color.dim, UI.font.small)
            dy = dy + UI.lineH(UI.font.small)
        end
        local dbBtn = FFButton:new(colW - 12 - dbW, warnTop, dbW, EH, "Disband faction",
            self, LasciviousFactionsSystemPanel.onDisbandClick, "danger")
        dbBtn:initialise(); dbBtn:instantiate(); dzCard:addChild(dbBtn)
        rowY = rowY + dzCard:setContentHeight(math.max(dy, warnTop + EH)) + UI.pad
    else
        rowY = rowY + UI.pad
    end

    -- Total content height so the pane scrolls exactly to the last card (no more).
    scroll:setScrollHeight(rowY)
end

function LasciviousFactionsSystemPanel:onSettingsSave(button)
    local tag = self.settingsTagEntry and self.settingsTagEntry:getInternalText() or nil
    local desc = self.settingsDescEntry and self.settingsDescEntry:getInternalText() or ""
    local motd = self.settingsMotdEntry and self.settingsMotdEntry:getInternalText() or ""
    send("setFactionInfo", { tag = tag, description = desc, motd = motd })
end

-- ---------------------------------------------------------------------------
-- Help / onboarding -- a static reference so the (large) feature set is
-- discoverable in-game. Auto-opened the first time a player opens the panel.
-- ---------------------------------------------------------------------------
-- Per-feature help topics. Each row on the Help tab opens a FactionHelpWindow showing
-- that topic's body. Optional systems are phrased "if your server enables it".
local HELP_TOPICS = {
    { title = "Getting started", body = {
        FF.text("UI_LFS_Help01", "Lascivious Factions System lets you create a faction, claim territory as a team, and defend it. Open this panel with J or the faction button."),
        FF.text("UI_LFS_Help02", "No faction yet? Create one or wait for an invitation. Invitations appear immediately as an Accept/Decline popup."),
        FF.text("UI_LFS_Help03", "The sidebar contains Overview, Members, Claims, Factions, Settings, and Help. Owners see extra controls; other members receive options allowed by their roles."),
    } },
    { title = "Claiming land", body = {
        FF.text("UI_LFS_Help04", "Open Claims, enable Draw, and drag a rectangle on the map. Green means valid; red means excessive size, too many areas, overlap, or prohibited proximity."),
        FF.text("UI_LFS_Help05", "Claim size grows with score. A faction starts with one disconnected area and unlocks another after every configured block of points."),
        FF.text("UI_LFS_Help06", "If score falls, existing areas remain. While above the limit, the faction may keep, rearrange without growing, or reduce its land, but cannot expand."),
        FF.text("UI_LFS_Help07", "Non-members cannot loot, build, or dismantle in protected areas. Submit claim sends the selection to the server for validation."),
    } },
    { title = FF.text("UI_LFS_HelpInvitesTitle", "Invites and joining a faction"), body = {
        FF.text("UI_LFS_Help08", "Membership is invitation-only. An authorised member opens Members and chooses Invite to see eligible connected players."),
        FF.text("UI_LFS_Help09", "The list contains only connected players who do not already belong to an LFS faction; no username needs to be typed."),
        FF.text("UI_LFS_Help10", "The invited player immediately receives a popup and chooses Accept or Decline."),
        FF.text("UI_LFS_Help11", "After a decline, that faction must wait before inviting the same player again: first 60 seconds, then one hour, with progressively longer waits."),
        FF.text("UI_LFS_Help12", "Pending invitations can be revoked from Members. Public listings and applications are not used."),
    } },
    { title = "Opening an area to outsiders", body = {
        FF.text("UI_LFS_Help13", "Each area has its own access: Private allows members only; Allies also allows allied factions; Public allows every player."),
        FF.text("UI_LFS_Help14", "Choose separately whether visitors may loot containers, build and craft, or destroy and move objects. Members still follow role permissions."),
        FF.text("UI_LFS_Help15", "Public areas may be away from the base and appear on everyone's map. The server limits how many each faction may maintain."),
        FF.text("UI_LFS_Help16", "Loot is validated by the server. Building and moving depend on client checks and should be treated as a convenience barrier."),
    } },
    { title = "Roles & permissions", body = {
        FF.text("UI_LFS_Help17", "Roles are permission sets defined by the owner on Members. They may allow claiming, setting respawn, building, moving objects, managing members, and starting raids."),
        FF.text("UI_LFS_Help18", "The owner always has every permission. Use Members to assign roles."),
        FF.text("UI_LFS_Help19", "Containers and safehouses are protected on the server; some building and crafting checks depend on the client."),
    } },
    { title = "Raids", body = {
        FF.text("UI_LFS_Help20", "A raid is a numerical-superiority siege. Choose a target in Factions > Raid and keep more attackers than defenders inside the claim for the required time."),
        FF.text("UI_LFS_Help21", "Victory frees the land; it is not transferred to attackers. Losing superiority resets progress, and reaching maximum duration gives defenders the win."),
        FF.text("UI_LFS_Help22", "The server may restrict hours and protect factions without online defenders. Attackers may abandon a raid, and admins may end it."),
    } },
    { title = "Allies, pacts & wars", body = {
        FF.text("UI_LFS_Help23", "Owners manage diplomacy in Factions > Relations. Alliances require request and acceptance; allies cannot raid one another."),
        FF.text("UI_LFS_Help24", "Non-aggression pacts have a duration and optional sharing terms. While active they block raids and wars, but either side may break them."),
        FF.text("UI_LFS_Help25", "Wars score points from raid victories and enemy kills. Surrender grants victory, and allies may join as a coalition."),
    } },
    { title = "Faction score", body = {
        FF.text("UI_LFS_Help26", "Each character earns configurable points from zombie kills and survived hours. On death, both totals for that player reset to zero."),
        FF.text("UI_LFS_Help27", "Faction score is the live sum of current members' characters. It defines new land size, unlocked disconnected areas, and leaderboard position."),
        FF.text("UI_LFS_Help28", "Death does not remove claimed land. If score falls below the requirement, the faction simply cannot grow until it recovers the limit."),
    } },
    { title = "Seasons & leaderboard", body = {
        FF.text("UI_LFS_Help29", "Leaderboard orders factions by current score. With seasons enabled, it may also show only points earned since the season began."),
        FF.text("UI_LFS_Help30", "Seasons have a fixed duration, roll automatically, and keep a short winner history."),
    } },
    { title = "Territory perks", body = {
        FF.text("UI_LFS_Help31", "When enabled, territory perks work while a member is inside their own claim. The safe zone periodically removes nearby zombies but does not stop repopulation."),
        FF.text("UI_LFS_Help32b", "Mood: reduces boredom, unhappiness, stress, panic and anger. Health: moderate healing plus pain, poison and sickness relief, and a very slight slowdown of zombie infection progression -- it never removes bites or guarantees a cure."),
        FF.text("UI_LFS_Help32c", "Fatigue: strongly speeds up tiredness and endurance recovery, without replacing real sleep. Needs: very lightly slows hunger, thirst and wetness. Each of the four can be turned off independently by the server."),
    } },
    { title = "On-screen feedback & chat", body = {
        FF.text("UI_LFS_Help33", "The top banner shows season position and active-war score. It may be hidden in Options > Mods > Lascivious Factions System."),
        FF.text("UI_LFS_Help34", "Enemy and wartime name tags appear red, and members are warned when a hostile enters the claim."),
        FF.text("UI_LFS_Help35", "Commands: /ff panel opens the panel; /f <message> talks to the faction; /ff create <name> and /ff info also work. Invitations are answered through their popup. Admins have /ff admin commands."),
    } },
}

function LasciviousFactionsSystemPanel:populateHelp()
    local innerW = self.content:getWidth() - 2 * UI.pad
    local top = 12

    -- Same scroll-pane host as the Settings tab (the topic list can exceed the window).
    local scroll = ISPanel:new(0, top, self.content:getWidth(), self.content:getHeight() - top)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    self.content:addChild(scroll)
    self.helpScroll = scroll
    self.activeScroll = scroll

    local colX = UI.pad
    local colW = innerW - 16                 -- leave room for the scrollbar
    local rowY = UI.pad
    local lh = UI.lineH(UI.font.body)

    -- Intro line, then one clickable button per topic; each opens a detail window.
    for _, line in ipairs(wrapText(FF.tr("Pick a topic for a detailed guide. Press J any time to open this panel."), UI.font.body, colW)) do
        local l = ISLabel:new(colX, rowY, lh, line, UI.color.dim.r, UI.color.dim.g, UI.color.dim.b, 1.0, UI.font.body, true)
        l:initialise(); scroll:addChild(l)
        rowY = rowY + lh
    end
    rowY = rowY + 8

    -- One row per topic inside a single grouped card, each showing the topic title
    -- with the opening sentence of its guide underneath. This was a stack of
    -- identical full-width ghost buttons carrying nothing but a title, so choosing
    -- between "Claiming land" and "Raids and wars" meant opening one to find out what
    -- was in it. The sub-line answers that without the round trip.
    local group = FFRowGroup:new(colX, rowY, colW)
    group:initialise(); group:instantiate()
    for i, topic in ipairs(HELP_TOPICS) do
        local blurb = topic.body and topic.body[1] or nil
        if blurb then
            -- First sentence only. Guarded: a paragraph with no full stop (or one that
            -- opens with an abbreviation) must still yield something readable.
            local cut = string.find(blurb, "%. ")
            blurb = cut and string.sub(blurb, 1, cut) or blurb
        end
        local row = FFRow:new(0, 0, colW, {
            title = topic.title, sub = blurb, icon = "ic_help",
            onClick = LasciviousFactionsSystemPanel.onOpenHelpTopic, target = self,
        })
        row.topicIndex = i
        row:initialise(); row:instantiate()
        group:add(row)
    end
    rowY = rowY + group:seal() + UI.pad
    scroll:addChild(group)

    scroll:setScrollHeight(rowY)
end

function LasciviousFactionsSystemPanel:onOpenHelpTopic(button)
    local topic = button and HELP_TOPICS[button.topicIndex]
    if not topic then return end
    local w = FactionHelpWindow:new(topic)
    w:initialise(); w:instantiate(); w:addToUIManager()
    w:setAlwaysOnTop(true); w:bringToTop()
end

function LasciviousFactionsSystemPanel:onColorSwatchClick(button)
    if button.col then
        send("setFactionColor", { r = button.col.r, g = button.col.g, b = button.col.b })
    else
        send("setFactionColor", {})   -- reset to name-derived (Auto)
    end
end

-- TributeRateSlider's onCommit: target=self (the panel), value=0-100. The server
-- re-clamps independently (never trust the client) and re-syncs the real value.
function LasciviousFactionsSystemPanel:onTributeRateCommit(value)
    send("setFactionTributeRate", { value = value })
end

function LasciviousFactionsSystemPanel:onSettingToggle(button)
    local key = button.settingKey
    if key == "friendlyFire" then
        send("setFactionOption", { key = "friendlyFire", value = not button.on })
    elseif key == "shareMapWithAllies" then
        send("setFactionOption", { key = "shareMapWithAllies", value = not button.on })
    elseif key == "shareMemberLocations" then
        send("setFactionOption", { key = "shareMemberLocations", value = not button.on })
    elseif key == "allowAllyBuild" then
        send("setFactionOption", { key = "allowAllyBuild", value = not button.on })
    elseif key == "allowAllyMove" then
        send("setFactionOption", { key = "allowAllyMove", value = not button.on })
    end
end

-- Size a dialog to the content its createChildren just laid out, then re-centre it.
-- The constructor height is only a starting guess: at large font sizes the content is
-- far taller, and without this the footer buttons fall off the bottom of the window --
-- which on the Create dialog would leave a new player unable to make a faction at all.
local function fitDialog(dlg, bottom)
    local h = math.min(bottom + UI.pad, getCore():getScreenHeight() - 20)
    dlg:setHeight(h)
    dlg:setY(math.max(0, math.floor((getCore():getScreenHeight() - h) / 2)))
end

-- ===========================================================================
-- FactionCreateDialog : a modal for setting up a new faction up front. Reuses
-- the ColorSwatch / RolePermRow widgets + swatch palette from above. Toggle and
-- swatch state lives on the dialog until Create fires a single createFaction.
-- ===========================================================================
FactionCreateDialog = ISCollapsableWindow:derive("FactionCreateDialog")

function FactionCreateDialog:new()
    local w, h = 380, 476
    local x = (getCore():getScreenWidth() - w) / 2
    local y = (getCore():getScreenHeight() - h) / 2
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.title = FF.tr("Create Faction")
    o.resizable = false
    o.pvp = false
    o.color = nil
    o.swatches = {}
    o:setWantKeyEvents(true)   -- Escape = Cancel
    return o
end

-- Escape cancels the dialog (equivalent to the Cancel button); consume it so it doesn't
-- also open the pause menu. While a field is being typed in, Escape blurs it first.
function FactionCreateDialog:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE
end

function FactionCreateDialog:onKeyRelease(key)
    if key ~= Keyboard.KEY_ESCAPE then return end
    if not anyEntryFocused(self.nameEntry, self.tagEntry, self.descEntry) then self:close() end
end

function FactionCreateDialog:prerender()
    local th = self:titleBarHeight()
    local w, h = self:getWidth(), self:getHeight()
    local c = UI.color
    self:drawRect(0, th, w, h - th, 1.0, c.bg.r, c.bg.g, c.bg.b)
    self:drawRect(0, 0, w, th, 1.0, c.titlebar.r, c.titlebar.g, c.titlebar.b)
    self:drawRect(0, th - 2, w, 2, 1.0, c.accent.r, c.accent.g, c.accent.b)
    self:drawRectBorder(0, 0, w, h, 1.0, c.border.r, c.border.g, c.border.b)
    if self.title then
        self:drawTextCentre(self.title, math.floor(w / 2), math.floor((th - UI.fh(UI.font.title)) / 2),
            c.text.r, c.text.g, c.text.b, 1.0, UI.font.title)
    end
end

function FactionCreateDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = UI.pad
    local innerW = self:getWidth() - 2 * pad
    local y = self:titleBarHeight() + 12

    local EH = UI.rowH(UI.font.body)
    local function label(t)
        t = FF.tr(t)
        local l = ISLabel:new(pad, y, UI.fh(UI.font.body), t, UI.color.text.r, UI.color.text.g, UI.color.text.b, 1.0, UI.font.body, true)
        l:initialise(); self:addChild(l); y = y + UI.lineH(UI.font.body)
    end
    local function entry(w)
        local e = passWheel(ISTextEntryBox:new("", pad, y, w, EH))
        e:initialise(); e:instantiate(); self:addChild(e); y = y + EH + 8
        return e
    end

    label("Faction name")
    self.nameEntry = entry(innerW)
    label("Tag (short badge)")
    self.tagEntry = entry(160)
    -- Server now auto-generates a short tag from the faction name (initials of each
    -- word, or a few letters for a single word) when this is left blank, instead of
    -- falling back to the full name as the tag -- see generateTagFromName in
    -- LFS_Server.lua. New string via FF.text (not the label() helper above): label()
    -- pipes through FF.tr, which only resolves text already in its auto-generated
    -- KEYS table, and this string is new.
    local hint = ISLabel:new(pad, y, UI.fh(UI.font.small),
        FF.text("UI_LFS_TagAutoHint", "Deixe em branco para gerar automaticamente a partir do nome."),
        UI.color.dim.r, UI.color.dim.g, UI.color.dim.b, 1.0, UI.font.small, true)
    hint:initialise(); self:addChild(hint); y = y + UI.lineH(UI.font.small) + 4
    label("Description (shown on entry)")
    self.descEntry = entry(innerW)

    label("Accent colour")
    local size, gap = 26, 6
    local sx = pad
    local auto = ColorSwatch:new(sx, y, size, nil, true, self, FactionCreateDialog.onSwatch)
    auto:initialise(); auto:instantiate(); self:addChild(auto); self.swatches[#self.swatches + 1] = auto
    sx = sx + size + gap
    for _, col in ipairs(SETTINGS_SWATCHES) do
        local sw = ColorSwatch:new(sx, y, size, col, false, self, FactionCreateDialog.onSwatch)
        sw:initialise(); sw:instantiate(); self:addChild(sw); self.swatches[#self.swatches + 1] = sw
        sx = sx + size + gap
    end
    y = y + size + 12

    local function toggle(text, field)
        local row = RolePermRow:new(pad, y, innerW, nil, text, self[field], self, FactionCreateDialog.onToggle)
        row:initialise(); row:instantiate(); row.field = field; self:addChild(row)
        y = y + row:getHeight() + 2
    end
    toggle("Allow PvP between members", "pvp")
    y = y + 8

    -- Repeat the live requirement inside the modal as a defensive affordance. A
    -- player normally cannot open this dialog while blocked, but death or an admin
    -- changing the sandbox minimum can invalidate the requirement while it is open.
    local requirement = CreationRequirement:new(pad, y, innerW, nil)
    requirement:initialise(); requirement:instantiate(); self:addChild(requirement)
    y = y + requirement:getHeight() + 8

    local bw = (innerW - 10) / 2
    local cancel = FFButton:new(pad, y, bw, EH, "Cancel", self, FactionCreateDialog.onCancel, "ghost")
    cancel:initialise(); cancel:instantiate(); self:addChild(cancel)
    local create = FFButton:new(pad + bw + 10, y, bw, EH, "Create", self, FactionCreateDialog.onCreate, "primary", "ic_claim")
    create.disabledNeutral = true
    create:initialise(); create:instantiate(); self:addChild(create)
    self.createButton = create
    requirement.createButton = create
    local canCreate = factionCreationRequirement()
    create:setEnable(canCreate)
    fitDialog(self, y + EH)
end

function FactionCreateDialog:onToggle(button)
    local f = button.field
    self[f] = not self[f]
    button.on = self[f]
end

function FactionCreateDialog:onSwatch(button)
    self.color = button.col   -- {r,g,b} or nil (Auto)
    for _, sw in ipairs(self.swatches) do
        sw.selected = (sw.col == nil and self.color == nil) or colorsMatch(sw.col, self.color)
    end
end

function FactionCreateDialog:onCreate(button)
    -- Do not send and do not close if the character stopped satisfying the gate
    -- while this modal was open (death, or a live sandbox requirement change).
    if not factionCreationRequirement() then return end
    local name = self.nameEntry:getInternalText()
    if not name or name == "" then return end
    local args = {
        name = name,
        tag = self.tagEntry:getInternalText(),
        description = self.descEntry:getInternalText(),
        joinMode = "closed",
        friendlyFire = self.pvp,
        hideBanner = true,
    }
    if self.color then args.color = { r = self.color.r, g = self.color.g, b = self.color.b } end
    send("createFaction", args)
    self:close()
end

function FactionCreateDialog:onCancel(button)
    self:close()
end

function FactionCreateDialog:close()
    self:removeFromUIManager()
end

-- ===========================================================================
-- FactionPactDialog : compose a non-aggression pact contract before proposing it.
-- The proposer sets the duration and optional share clauses; Propose sends one
-- proposePact with the full contract. Reuses RolePermRow + FFButton.
-- ===========================================================================
FactionPactDialog = ISCollapsableWindow:derive("FactionPactDialog")

local PACT_DURATIONS = {
    { "Indefinite (until broken)", 0 },
    { "3 days", 3 }, { "7 days", 7 }, { "14 days", 14 }, { "30 days", 30 },
}

function FactionPactDialog:new(target)
    local w, h = 400, 386
    local x = (getCore():getScreenWidth() - w) / 2
    local y = (getCore():getScreenHeight() - h) / 2
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.title = FF.tr("Propose Pact")
    o.resizable = false
    o.target = target
    o.shareMap = false
    o.shareLocations = false
    o:setWantKeyEvents(true)
    return o
end

function FactionPactDialog:isKeyConsumed(key) return key == Keyboard.KEY_ESCAPE end
function FactionPactDialog:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:close() end
end

FactionPactDialog.prerender = FactionCreateDialog.prerender

function FactionPactDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = UI.pad
    local innerW = self:getWidth() - 2 * pad
    local y = self:titleBarHeight() + 12

    local function label(t, color)
        t = FF.tr(t)
        color = color or UI.color.text
        local l = ISLabel:new(pad, y, UI.fh(UI.font.body), t, color.r, color.g, color.b, 1.0, UI.font.body, true)
        l:initialise(); self:addChild(l); y = y + UI.lineH(UI.font.body)
    end
    local EH = UI.rowH(UI.font.body)

    label(FF.text("UI_LFS_PactWith", "Pact with %s", tostring(self.target)), UI.color.accent)
    label("Neither side may raid or declare war while active.", UI.color.dim)
    y = y + 6

    label("Duration")
    self.durationCombo = ISComboBox:new(pad, y, innerW, EH, self, nil)
    self.durationCombo:initialise(); self.durationCombo:instantiate()
    self.durationCombo.backgroundColor = UI.color.panel
    self.durationCombo.borderColor = UI.color.border
    for _, d in ipairs(PACT_DURATIONS) do
        local shown = d[2] == 0 and FF.tr(d[1]) or FF.text("UI_LFS_PactDays", "%d days", d[2])
        self.durationCombo:addOptionWithData(shown, d[2])
    end
    self.durationCombo.selected = 1
    self:addChild(self.durationCombo); y = y + EH + 10

    label("Optional terms")
    local function toggle(text, field)
        local row = RolePermRow:new(pad, y, innerW, nil, text, self[field], self, FactionPactDialog.onToggle)
        row:initialise(); row:instantiate(); row.field = field; self:addChild(row)
        y = y + row:getHeight() + 2
    end
    toggle("Share our claim map with each other", "shareMap")
    toggle("Share our member locations with each other", "shareLocations")
    y = y + 10

    local bw = (innerW - 10) / 2
    local cancel = FFButton:new(pad, y, bw, EH, "Cancel", self, FactionPactDialog.onCancel, "ghost")
    cancel:initialise(); cancel:instantiate(); self:addChild(cancel)
    local propose = FFButton:new(pad + bw + 10, y, bw, EH, "Propose", self, FactionPactDialog.onPropose, "primary")
    propose:initialise(); propose:instantiate(); self:addChild(propose)
    fitDialog(self, y + EH)
end

function FactionPactDialog:onToggle(button)
    local f = button.field
    self[f] = not self[f]
    button.on = self[f]
end

function FactionPactDialog:onPropose()
    if not self.target then return self:close() end
    local combo = self.durationCombo
    local days = combo and combo:getOptionData(combo.selected) or 0
    send("proposePact", {
        target = self.target,
        durationDays = days,
        shareMap = self.shareMap,
        shareLocations = self.shareLocations,
    })
    self:close()
end

function FactionPactDialog:onCancel() self:close() end
function FactionPactDialog:close() self:removeFromUIManager() end

-- ===========================================================================
-- TributeAmountDialog : prompts for a credit amount, then delegates to the
-- always-loaded client transaction owner in LFS_Client.lua. It retains one
-- immutable request id/payload through lost replies, retries and reconnects.
-- ===========================================================================
TributeAmountDialog = ISCollapsableWindow:derive("TributeAmountDialog")

-- mode: "deposit" | "withdraw" | "donate" -- deposit and donate send the same
-- command (server-side handleTributeContribute treats them identically); only the
-- title/button label and which command withdraw uses differ.
function TributeAmountDialog:new(mode)
    local w, h = 320, 170
    local x = (getCore():getScreenWidth() - w) / 2
    local y = (getCore():getScreenHeight() - h) / 2
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.mode = mode
    local titles = {
        deposit = FF.text("UI_LFS_TributeDepositTitle", "Depositar tributo"),
        withdraw = FF.text("UI_LFS_TributeWithdrawTitle", "Sacar tributo"),
        donate = FF.text("UI_LFS_TributeDonateTitle", "Doar para a facção"),
    }
    o.title = titles[mode] or titles.deposit
    o.resizable = false
    o:setWantKeyEvents(true)
    return o
end

function TributeAmountDialog:isKeyConsumed(key) return key == Keyboard.KEY_ESCAPE end
function TributeAmountDialog:onKeyRelease(key)
    if key ~= Keyboard.KEY_ESCAPE then return end
    if not anyEntryFocused(self.amountEntry) then self:close() end
end

TributeAmountDialog.prerender = FactionCreateDialog.prerender

function TributeAmountDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = UI.pad
    local innerW = self:getWidth() - 2 * pad
    local y = self:titleBarHeight() + 12
    local EH = UI.rowH(UI.font.body)

    local label = ISLabel:new(pad, y, UI.fh(UI.font.body),
        FF.text("UI_LFS_TributeAmountLabel", "Quantidade de créditos"), UI.color.text.r, UI.color.text.g,
        UI.color.text.b, 1.0, UI.font.body, true)
    label:initialise(); self:addChild(label)
    y = y + UI.lineH(UI.font.body)

    -- Deposit/Donate spend the player's OWN Shop balance (Withdraw pulls from the
    -- faction treasury instead, shown on the Tribute tab itself, not here). Cross-
    -- mod read of Shop's client-cached state -- may be nil if the player never
    -- opened the shop this session, so request a fresh copy and just omit the
    -- hint on this first open if it isn't back yet.
    if self.mode ~= "withdraw" then
        if LasciviousShopClient and type(LasciviousShopClient.requestState) == "function" then
            pcall(LasciviousShopClient.requestState)
        end
        local balanceState = LasciviousShopClient and LasciviousShopClient.state
        if balanceState then
            local amount = tonumber(balanceState.balance) or 0
            if amount ~= amount or amount == math.huge or amount == -math.huge then amount = 0 end
            local formatted = (string.gsub(string.format("%.2f", amount), "%.", ","))
            local LS = _G.LasciviousShop
            if LS and type(LS.formatCreditsFixed) == "function" then
                local ok, shopFormatted = pcall(LS.formatCreditsFixed, balanceState.balance)
                if ok and shopFormatted ~= nil then formatted = tostring(shopFormatted) end
            end
            local balanceLabel = ISLabel:new(pad, y, UI.fh(UI.font.small),
                FF.text("UI_LFS_TributeYourBalance", "(Seu saldo: %s)",
                    formatted),
                UI.color.dim.r, UI.color.dim.g, UI.color.dim.b, 1.0, UI.font.small, true)
            balanceLabel:initialise(); self:addChild(balanceLabel)
            y = y + UI.lineH(UI.font.small)
        end
    end
    y = y + 4

    self.amountEntry = passWheel(ISTextEntryBox:new("", pad, y, innerW, EH))
    self.amountEntry:initialise(); self.amountEntry:instantiate()
    self.amountEntry.backgroundColor = UI.color.panel
    self.amountEntry.borderColor = UI.color.border
    self:addChild(self.amountEntry)
    y = y + EH + 16

    local bw = (innerW - 10) / 2
    local cancel = FFButton:new(pad, y, bw, EH, FF.tr("Cancel"), self, TributeAmountDialog.onCancel, "ghost")
    cancel:initialise(); cancel:instantiate(); self:addChild(cancel)
    local confirmLabel = self.mode == "withdraw" and FF.text("UI_LFS_TributeWithdrawAction", "Sacar")
        or (self.mode == "donate" and FF.text("UI_LFS_TributeDonateAction", "Doar")
            or FF.text("UI_LFS_TributeDepositAction", "Depositar"))
    local confirm = FFButton:new(pad + bw + 10, y, bw, EH, confirmLabel, self, TributeAmountDialog.onConfirm, "primary")
    confirm:initialise(); confirm:instantiate(); self:addChild(confirm)
    fitDialog(self, y + EH)
    if self.amountEntry then self.amountEntry:focus() end
end

function TributeAmountDialog:onConfirm()
    local raw = self.amountEntry and self.amountEntry:getText() or ""
    local amount = tonumber((tostring(raw):gsub(",", ".")))
    if not amount or amount ~= amount or amount <= 0 then
        local player = getPlayer()
        if player then
            player:setHaloNote(FF.text("UI_LFS_TributeInvalidAmount", "Informe uma quantidade válida."),
                255, 120, 120, 250)
        end
        return
    end
    local command = self.mode == "withdraw" and "withdrawTribute"
        or (self.mode == "donate" and "donateTribute" or "depositTribute")
    local ok, reason
    if type(FF.requestTribute) == "function" then
        ok, reason = FF.requestTribute(command, amount)
    else
        ok, reason = false, "unavailable"
    end
    if ok then
        self:close()
    else
        local player = getPlayer()
        if player then
            player:setHaloNote(reason == "awaiting"
                and FF.text("UI_LFS_TributeMsgAwaiting", "Uma operação de tributo já aguarda resposta do servidor.")
                or FF.text("UI_LFS_TributeMsgShopUnavailable",
                    "O serviço de créditos está indisponível no momento. Tente novamente em instantes."),
                255, 180, 80, 250)
        end
    end
end

function TributeAmountDialog:onCancel() self:close() end
function TributeAmountDialog:close() self:removeFromUIManager() end

-- ===========================================================================
-- TributeRateSlider : a plain 0-100 drag slider for the faction settings tab.
-- Built from the same mouse-capture mechanics as a resize grip (capture on down,
-- recompute from the drag position, release + commit on up) -- no vanilla widget
-- or existing widget elsewhere in this mod does free 0-100 dragging.
-- ===========================================================================
TributeRateSlider = ISPanel:derive("TributeRateSlider")

function TributeRateSlider:new(x, y, width, height, value, onCommit, target)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self); self.__index = self
    o.background = false
    o.value = math.floor(math.max(0, math.min(100, tonumber(value) or 0)))
    o.dragging = false
    o.onCommit = onCommit
    o.commitTarget = target
    return o
end

-- External updates (a fresh server sync while the settings tab is open) never
-- clobber a value the player is actively dragging.
function TributeRateSlider:setValue(value)
    if self.dragging then return end
    self.value = math.floor(math.max(0, math.min(100, tonumber(value) or 0)))
end

function TributeRateSlider:valueFromMouseX(mx)
    local w = self:getWidth()
    if w <= 0 then return self.value end
    local frac = math.max(0, math.min(1, mx / w))
    return math.floor(frac * 100 + 0.5)
end

function TributeRateSlider:onMouseDown(x, y)
    self.dragging = true
    self:setCapture(true)
    self.value = self:valueFromMouseX(x)
    return true
end

function TributeRateSlider:onMouseMove(dx, dy)
    if not self.dragging then return end
    self.value = self:valueFromMouseX(self:getMouseX())
end

function TributeRateSlider:onMouseMoveOutside(dx, dy)
    if not self.dragging then return end
    self.value = self:valueFromMouseX(self:getMouseX())
end

function TributeRateSlider:onMouseUp(x, y)
    if not self.dragging then return end
    self.dragging = false
    self:setCapture(false)
    if self.onCommit then self.onCommit(self.commitTarget, self.value) end
end

function TributeRateSlider:onMouseUpOutside(x, y)
    self:onMouseUp(x, y)
end

function TributeRateSlider:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    local trackH = math.max(4, math.floor(h / 3))
    local trackY = math.floor((h - trackH) / 2)
    UI.roundRect(self, 0, trackY, w, trackH, math.floor(trackH / 2), 1.0, c.track)
    local fillW = math.floor(w * (self.value / 100))
    if fillW > 0 then
        UI.roundRect(self, 0, trackY, math.max(trackH, fillW), trackH, math.floor(trackH / 2), 1.0, c.accent)
    end
    local knobSize = math.min(h, 18)
    local knobY = math.floor((h - knobSize) / 2)
    local knobX = math.max(0, math.min(w - knobSize, fillW - math.floor(knobSize / 2)))
    UI.roundRect(self, knobX, knobY, knobSize, knobSize, math.floor(knobSize / 2), 1.0,
        self.dragging and c.accentText or c.text)
    self:drawText(tostring(self.value) .. "%", w + 10, math.floor((h - UI.fh(UI.font.body)) / 2),
        c.accentText.r, c.accentText.g, c.accentText.b, 1.0, UI.font.body)
end

UI.installDimming(TributeRateSlider)

-- ===========================================================================
-- FactionAreaAccessDialog : open ONE logical claim area to allies or to everyone, and
-- pick exactly which permissions that grant carries.
--
-- Edits the claim map's WORKING SET, not the server -- the Claims tab is a draft
-- editor (Draw / Erase / Clear / Submit) and an access change is just another
-- pending edit, applied with the rest on Submit claim. That is also why there is
-- no server handler for this: Handlers.claim already replaces the whole array.
--
-- Holds every backing rectangle TABLE, not their indexes: an L-shaped area may use
-- several non-overlapping rectangles internally while remaining one editable area.
-- ===========================================================================
FactionAreaAccessDialog = ISCollapsableWindow:derive("FactionAreaAccessDialog")

local AREA_LEVELS = {
    { "private", "Private", "Only our own members." },
    { "allies",  "Allies",  "Our members plus allied factions' members." },
    { "public",  "Public",  "Everyone, including factions we are at war with." },
}

local AREA_GRANT_ROWS = {
    { "loot",  "Can loot containers here" },
    { "build", "Can build & craft here" },
    { "move",  "Can destroy & move objects here" },
}

function FactionAreaAccessDialog.open(map, index)
    local group = map and map:areaGroups()[index]
    if not group then return end
    local dlg = FactionAreaAccessDialog:new(map, group)
    dlg:initialise()
    dlg:addToUIManager()
    dlg:setAlwaysOnTop(true)
    dlg:bringToTop()
    return dlg
end

function FactionAreaAccessDialog:new(map, group)
    local w, h = 400, 330
    local x = (getCore():getScreenWidth() - w) / 2
    local y = (getCore():getScreenHeight() - h) / 2
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.title = FF.tr("Area Access")
    o.resizable = false
    o.map = map
    o.rects = group.rects
    o.bounds = { group.x1, group.y1, group.x2, group.y2 }
    o.area = group.area
    o.access = FF.areaAccess(group.rect)
    o.grants = FF.areaGrants(group.rect)
    o:setWantKeyEvents(true)
    return o
end

function FactionAreaAccessDialog:isKeyConsumed(key) return key == Keyboard.KEY_ESCAPE end
function FactionAreaAccessDialog:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:close() end
end

FactionAreaAccessDialog.prerender = FactionCreateDialog.prerender

function FactionAreaAccessDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = UI.pad
    local innerW = self:getWidth() - 2 * pad
    local y = self:titleBarHeight() + 12
    local r = self.bounds

    local function label(t, color, font)
        t = FF.tr(t)
        color = color or UI.color.text
        font = font or UI.font.body
        local l = ISLabel:new(pad, y, UI.fh(font), t, color.r, color.g, color.b, 1.0, font, true)
        l:initialise(); self:addChild(l); y = y + UI.lineH(font)
        return l
    end
    local EH = UI.rowH(UI.font.body)

    label(FF.text("UI_LFS_ClaimAreaTiles", "%d quadrados", self.area), UI.color.accent)
    label("Your own members are never affected by this.", UI.color.dim, UI.font.small)
    y = y + 8

    -- Level row. MaxPublicClaimAreas = 0 is the admin kill switch for public areas,
    -- so offer the button but leave it disabled rather than silently hiding it.
    local publicAllowed = FF.getOptions().maxPublicClaimAreas > 0
    local bw = math.floor((innerW - 2 * 8) / 3)
    self.levelBtns = {}
    for i, lv in ipairs(AREA_LEVELS) do
        local b = FFButton:new(pad + (i - 1) * (bw + 8), y, bw, EH, lv[2],
            self, FactionAreaAccessDialog.onLevel,
            (self.access == lv[1]) and "primary" or "ghost")
        b:initialise(); b:instantiate()
        b.level = lv[1]
        b.tooltip = FF.tr(lv[3])
        if lv[1] == "public" and not publicAllowed then
            b:setEnable(false)
            b.tooltip = FF.tr("Public areas are disabled on this server (MaxPublicClaimAreas = 0).")
        end
        self:addChild(b)
        self.levelBtns[#self.levelBtns + 1] = b
    end
    y = y + EH + 6
    self.levelDesc = label("", UI.color.dim, UI.font.small)
    y = y + 8

    self.grantRows = {}
    for _, g in ipairs(AREA_GRANT_ROWS) do
        local row = RolePermRow:new(pad, y, innerW, nil, g[2], self.grants[g[1]] == true,
            self, FactionAreaAccessDialog.onGrant)
        row:initialise(); row:instantiate(); row.grantKey = g[1]
        self:addChild(row); y = y + row:getHeight() + 2
        self.grantRows[#self.grantRows + 1] = row
    end
    y = y + 4

    -- Standing caution: opening loot is the intended shop case, but build/move let an
    -- outsider alter the place, which is what people regret.
    self.warnLabel = label("", UI.color.warn, UI.font.small)
    y = y + 6

    local hw = math.floor((innerW - 10) / 2)
    local cancel = FFButton:new(pad, y, hw, EH, "Cancel", self, FactionAreaAccessDialog.onCancel, "ghost")
    cancel:initialise(); cancel:instantiate(); self:addChild(cancel)
    local apply = FFButton:new(pad + hw + 10, y, hw, EH, "Apply", self, FactionAreaAccessDialog.onApply, "primary")
    apply:initialise(); apply:instantiate(); self:addChild(apply)
    fitDialog(self, y + EH)

    self:syncControls()
end

-- Reflect self.access / self.grants onto the widgets. A private area grants nothing,
-- so its toggles go read-only (RolePermRow dims itself when onclick is nil) rather
-- than letting you set a grant that would be discarded on Apply.
function FactionAreaAccessDialog:syncControls()
    for _, b in ipairs(self.levelBtns or {}) do
        b.variant = (b.level == self.access) and "primary" or "ghost"
    end
    local private = (self.access == "private")
    for _, row in ipairs(self.grantRows or {}) do
        row.on = (not private) and (self.grants[row.grantKey] == true) or false
        row.onclick = private and nil or FactionAreaAccessDialog.onGrant
    end
    if self.levelDesc then
        local desc = ""
        for _, lv in ipairs(AREA_LEVELS) do if lv[1] == self.access then desc = lv[3] end end
        self.levelDesc:setName(desc)
    end
    if self.warnLabel then
        -- One line, so pick the most surprising warning: outsiders altering the place
        -- is the one people regret.
        local warn = ""
        if not private and (self.grants.build or self.grants.move) then
            warn = "Outsiders will be able to alter this area."
        end
        self.warnLabel:setName(warn)
    end
end

function FactionAreaAccessDialog:onLevel(button)
    if not button.level then return end
    self.access = button.level
    -- Opening an area for the first time defaults to loot -- "help yourself" -- rather
    -- than carrying over nothing at all and looking broken.
    if self.access ~= "private"
        and not (self.grants.loot or self.grants.build or self.grants.move) then
        self.grants.loot = true
    end
    self:syncControls()
end

function FactionAreaAccessDialog:onGrant(button)
    local k = button.grantKey
    if not k then return end
    self.grants[k] = not (self.grants[k] == true)
    self:syncControls()
end

function FactionAreaAccessDialog:onApply()
    local map = self.map
    -- applyAreaAccess identity-checks every fragment because the area may have been
    -- erased/reloaded while this window was open.
    if map then map:applyAreaAccess(self.rects, self.access, self.grants) end
    self:close()
end

function FactionAreaAccessDialog:onCancel() self:close() end
function FactionAreaAccessDialog:close() self:removeFromUIManager() end

-- ===========================================================================
-- FactionHelpWindow : a per-feature detail window opened from the Help tab. Shows the
-- topic title and its body paragraphs, word-wrapped in a scroll pane.
-- ===========================================================================
FactionHelpWindow = ISCollapsableWindow:derive("FactionHelpWindow")

function FactionHelpWindow:new(topic)
    local w, h = 500, 470
    local x = (getCore():getScreenWidth() - w) / 2
    local y = (getCore():getScreenHeight() - h) / 2
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.title = FF.tr(topic and topic.title or "Help")
    o.topic = topic
    o.resizable = false
    o:setWantKeyEvents(true)
    return o
end

function FactionHelpWindow:isKeyConsumed(key) return key == Keyboard.KEY_ESCAPE end
function FactionHelpWindow:onKeyRelease(key) if key == Keyboard.KEY_ESCAPE then self:close() end end

FactionHelpWindow.prerender = FactionCreateDialog.prerender

function FactionHelpWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = UI.pad
    local th = self:titleBarHeight()
    local btnH = UI.rowH(UI.font.body) + 16
    local scroll = ISPanel:new(pad, th + 8, self:getWidth() - 2 * pad, self:getHeight() - th - 8 - btnH)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    self:addChild(scroll)

    local lh = UI.lineH(UI.font.body)
    local textW = self:getWidth() - 2 * pad - 24
    local y = 4
    for _, para in ipairs((self.topic and self.topic.body) or {}) do
        for _, line in ipairs(wrapText(para, UI.font.body, textW)) do
            local l = ISLabel:new(6, y, lh, line,
                UI.color.text.r, UI.color.text.g, UI.color.text.b, 1.0, UI.font.body, true)
            l:initialise(); scroll:addChild(l)
            y = y + lh
        end
        y = y + lh   -- blank line between paragraphs
    end
    scroll:setScrollHeight(y)

    local closeH = UI.rowH(UI.font.body)
    local closeW = math.max(110, UI.buttonWidth("Close", false, closeH))
    local close = FFButton:new(self:getWidth() - pad - closeW, self:getHeight() - btnH + 8, closeW, closeH,
        "Close", self, FactionHelpWindow.onClose, "primary")
    close:initialise(); close:instantiate(); self:addChild(close)
end

function FactionHelpWindow:onClose() self:close() end
function FactionHelpWindow:close() self:removeFromUIManager() end

-- ---------------------------------------------------------------------------
-- Claims
-- ---------------------------------------------------------------------------
function LasciviousFactionsSystemPanel:populateClaims()
    -- Refs cleared each build; content:clearChildren() removed last build's widgets
    -- (the cached map object survives -- we hold it and re-add it below).
    self.claimDrawBtn, self.claimSubmitBtn, self.claimClearBtn = nil, nil, nil
    self.claimEraseBtn, self.claimCapBar, self.claimShopBtn = nil, nil, nil

    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end

    local x = UI.pad
    local innerW = self.content:getWidth() - 2 * UI.pad
    local y = self:addHeader(name, faction, username)

    -- Gate on the actual "claim" permission, not a hardcoded role name -- otherwise a
    -- member in a custom-named role (or a renamed officer role) that was granted claim
    -- rights is wrongly locked out here even though the server (Handlers.claim) allows it.
    self.canManageClaims = FF.roleCan(faction, username, "claim")

    -- Caçador max level (10) only -- see the toggle itself, below the map, for why.
    local showHunterMapToggle = FF.upgradeLevel(faction, "hunter") >= 10

    local claimed = FF.totalArea(faction.claims)
    local maxTiles = FF.maxClaimTiles(FF.factionScore(faction))

    -- Compact capacity bar. It doubles as the live claim readout: refreshClaimControls
    -- retargets it at the map's pending selection while editing (green/red), so the
    -- tile and area counts have one home instead of a second label competing for room
    -- in the control row below the map.
    -- The only FFBar with a label, so the only one whose height must follow the font.
    local capBarH = math.max(18, UI.rowH(UI.font.small))
    local capBar = FFBar:new(x, y, innerW, capBarH)
    capBar:initialise()
    capBar.fraction = (maxTiles > 0) and (claimed / maxTiles) or 0
    capBar.label = FF.text("UI_LFS_DynamicTiles", "%d / %d tiles",
        claimed, math.floor(maxTiles + 0.5))
    self.content:addChild(capBar)
    self.claimCapBar = capBar
    y = y + capBarH + 10

    -- Side column listing the individual claim areas, per the redesign. It costs
    -- horizontal room, and the map is a drag-to-draw surface -- at the 620px minimum
    -- window width the map would drop to ~225px, too small to work on -- so the
    -- column only appears once there is width to spare. showSection re-runs on every
    -- resize, so this flips automatically as the window is dragged.
    -- 220 rather than 200 since the area rows gained an access badge; the width
    -- threshold moves with it so the drag-to-draw map keeps the same room it had.
    local COLUMN_W, COLUMN_GAP = 220, 14
    local showColumn = self.content:getWidth() >= 580
    local mapW = showColumn and (innerW - COLUMN_W - COLUMN_GAP) or innerW

    -- Control-row geometry. Widths come from the measured labels -- including the
    -- wider "Drawing..." / "Erasing..." toggle states -- rather than fixed numbers,
    -- so the row can't collide at a different UI scale or in a translation. The row
    -- spans the full content width: the area column stops at the bottom of the map,
    -- so there is nothing down here for the right-hand buttons to slide under.
    local BTN_H, BTN_GAP, ROW_GAP = UI.rowH(UI.font.body), 8, 10
    local drawW = math.max(UI.buttonWidth("Draw claim", true, BTN_H), UI.buttonWidth("Drawing...", true, BTN_H))
    local eraseW = math.max(UI.buttonWidth("Erase", true, BTN_H), UI.buttonWidth("Erasing...", true, BTN_H))
    local clearW = UI.buttonWidth("Clear", false, BTN_H)
    local submitW = UI.buttonWidth("Submit claim", true, BTN_H)
    -- Four across, or two stacked pairs when they don't fit -- never overlapping.
    local editOneRow = (drawW + eraseW + clearW + submitW + 3 * BTN_GAP) <= innerW

    -- Caçador level-10 perk button -- a plain FFButton (not the sliding FFToggle
    -- switch this used at first: it read as visually out of place next to the
    -- button row, per explicit feedback), sized for whichever of its two labels
    -- is wider so it never resizes when clicked. Tries to sit on the SAME row as
    -- Draw/Erase (only possible in the one-row layout, which is the only case
    -- with spare width beyond the 4 buttons' own measured widths -- the stacked-
    -- pairs layout stretches Draw/Erase to exactly half innerW each, leaving no
    -- room for a 5th control there); falls back to its own compact row otherwise.
    local hunterOffLabel = FF.text("UI_LFS_HunterMapToggleOff", "Mostrar detecções no mapa")
    local hunterOnLabel = FF.text("UI_LFS_HunterMapToggleOn", "Não mostrar detecções no mapa")
    local hunterBtnW = showHunterMapToggle and math.max(
        UI.buttonWidth(hunterOffLabel, false, BTN_H),
        UI.buttonWidth(hunterOnLabel, false, BTN_H)) or 0
    -- Only possible when editOneRow: the OTHER layout stretches Draw/Erase to
    -- exactly half innerW each (see "Two stacked pairs of equal halves" below),
    -- which leaves no genuine spare width for a 3rd control no matter what a
    -- natural-width sum here would suggest.
    local hunterOnMainRow = false
    if showHunterMapToggle and self.canManageClaims and editOneRow then
        local rowW = drawW + BTN_GAP + eraseW + BTN_GAP + hunterBtnW
            + BTN_GAP + clearW + BTN_GAP + submitW
        hunterOnMainRow = rowW <= innerW
    end

    -- The shop button gets a row of its own rather than being squeezed in as a fifth
    -- button: it is the entry point to a feature players were not finding at all, so
    -- it needs to read as its own thing, and a fifth button would break the one-row
    -- layout at every window width anyway.
    -- Sized for the longer of its two titles, like Draw/Erase, so arming it can't
    -- clip the label.
    local SHOP_LABEL = "Make a Public Area"
    local shopW = math.min(innerW, math.max(
        UI.buttonWidth(SHOP_LABEL, true, BTN_H),
        UI.buttonWidth("Drag out the area...", true, BTN_H)))

    -- Reserve a block at the bottom for controls so the map ends exactly where they
    -- start (members get a single notice row there instead). With the area column up,
    -- Unclaim / Set respawn live in it and don't need a row of their own.
    local controlRows = 1
    if self.canManageClaims then
        controlRows = editOneRow and 1 or 2
        if not showColumn then controlRows = controlRows + 1 end
        controlRows = controlRows + 1   -- the shop-claim row
    end
    -- Caçador level-10 perk: any member (not just claim editors -- this is a personal
    -- map preference, not a claim-editing action) can opt into always seeing the
    -- upgrade's detection circles on the real world map/minimap, not just this
    -- embedded one. Only needs its OWN reserved row when it couldn't fit beside
    -- Draw/Erase (hunterOnMainRow, computed above) -- e.g. a non-editor member,
    -- who never reaches the Draw/Erase row at all, or a window too narrow to fit
    -- it on that row even when editing controls ARE shown.
    if showHunterMapToggle and not hunterOnMainRow then controlRows = controlRows + 1 end
    local RESERVE = ROW_GAP + controlRows * BTN_H + (controlRows - 1) * ROW_GAP + UI.pad
    local mapY = y
    local mapH = self.content:getHeight() - mapY - RESERVE

    -- Embedded map, created once (ISMiniMapInner init is heavy) and re-added on
    -- every visit to this tab.
    if not self.claimMap then
        self.claimMap = FFClaimMap:new(x, mapY, mapW, mapH)
        self.claimMap:initialise()
        self.claimMap:instantiate()
    end
    self.claimMap:setX(x)
    self.claimMap:setY(mapY)
    if self.claimMap.resizeTo then self.claimMap:resizeTo(mapW, mapH) end   -- follow window resizes
    self.content:addChild(self.claimMap)
    self.claimMap:refresh()

    local cy = mapY + mapH + 10

    if self.claimMap.failed then
        local note = Notice:new(x, cy, innerW, "Map unavailable -- is PhunZones loaded?", UI.color.bad, "ic_flame")
        note:initialise(); self.content:addChild(note)
        return
    end

    -- Own-row fallback: drawn ahead of the canManageClaims branch below (and its own
    -- early return) so EVERY member reaches it even when it can't fit beside Draw/
    -- Erase -- this is a personal viewing preference, not a claim edit action, so it
    -- must not be gated by the "claim" role permission. (When hunterOnMainRow is
    -- true it's drawn beside Erase instead, further down where that row exists.)
    -- Persisted client-side only (player:getModData(), same mechanism
    -- LFS_TerritoryOverlay.lua uses for its own saved position) -- purely a local
    -- render choice, nothing here needs the server at all.
    if showHunterMapToggle and not hunterOnMainRow then
        local player = getPlayer()
        local active = player and player:getModData().LFS_hunterShowOnWorldMap == true
        local label = active and hunterOnLabel or hunterOffLabel
        local hunterBtn = FFButton:new(x, cy, hunterBtnW, BTN_H, label,
            self, LasciviousFactionsSystemPanel.onHunterAlwaysShowToggle, active and "primary" or "ghost")
        hunterBtn:initialise(); hunterBtn:instantiate()
        self.content:addChild(hunterBtn)
        cy = cy + BTN_H + ROW_GAP
    end

    if showColumn then
        local colX = x + mapW + COLUMN_GAP
        -- Editors get the two stacked actions under the list; everyone gets the list.
        local btnBlock = self.canManageClaims and (2 * BTN_H + 8 + 10) or 0
        local areaList = ClaimAreaList:new(colX, mapY, COLUMN_W, mapH - btnBlock,
            self.claimMap, self.canManageClaims)
        areaList:initialise(); self.content:addChild(areaList)

        if self.canManageClaims then
            local by = mapY + mapH - (2 * BTN_H + 8)
            local respawnBtn = FFButton:new(colX, by, COLUMN_W, BTN_H, "Set respawn here",
                self, LasciviousFactionsSystemPanel.onSetRespawnClick, "ghost", "ic_respawn")
            respawnBtn:initialise(); respawnBtn:instantiate()
            -- Advisory only (server re-checks setRespawn -> respawn_must_be_in_claim).
            local inClaim = FF.pointInClaim(faction, math.floor(getPlayer():getX()), math.floor(getPlayer():getY()))
            respawnBtn:setEnable(inClaim)
            if not inClaim then
                respawnBtn.tooltip = FF.tr("Stand inside your claim to set the respawn point")
            end
            self.content:addChild(respawnBtn)

            local unclaimBtn = FFButton:new(colX, by + BTN_H + 8, COLUMN_W, BTN_H, "Unclaim all",
                self, LasciviousFactionsSystemPanel.onUnclaimClick, "danger", "ic_unclaim")
            unclaimBtn:initialise(); unclaimBtn:instantiate(); self.content:addChild(unclaimBtn)
        end
    end

    if not self.canManageClaims then
        local note = Notice:new(x, cy, mapW, "You don't have permission to edit claims.", UI.color.dim, nil)
        note:initialise(); self.content:addChild(note)
        return
    end

    -- Edit controls: Draw | Erase packed left, Clear | Submit flush right, all inside
    -- innerW. The live tile/area counts now ride on the capacity bar above the map
    -- (see refreshClaimControls), which is what used to make this row overflow.
    local mkBtn = function(bx, by, bw, label, fn, variant, icon, tip)
        local b = FFButton:new(bx, by, bw, BTN_H, label, self, fn, variant, icon)
        b:initialise(); b:instantiate()
        b.tooltip = tip
        self.content:addChild(b)
        return b
    end

    local row2Y = cy + BTN_H + ROW_GAP
    local drawTip = FF.text("UI_LFS_ClaimDrawTip", "Drag to mark territory.")
    local eraseTip = FF.text("UI_LFS_ClaimEraseTip", "Enable Erase mode and click an area to remove it.")

    if editOneRow then
        self.claimDrawBtn = mkBtn(x, cy, drawW, "Draw claim", LasciviousFactionsSystemPanel.onClaimDrawToggle, "ghost", "ic_claim", drawTip)
        self.claimEraseBtn = mkBtn(x + drawW + BTN_GAP, cy, eraseW, "Erase", LasciviousFactionsSystemPanel.onClaimEraseToggle, "ghost", "ic_unclaim", eraseTip)
        if hunterOnMainRow then
            local player = getPlayer()
            local active = player and player:getModData().LFS_hunterShowOnWorldMap == true
            mkBtn(x + drawW + BTN_GAP + eraseW + BTN_GAP, cy, hunterBtnW,
                active and hunterOnLabel or hunterOffLabel,
                LasciviousFactionsSystemPanel.onHunterAlwaysShowToggle, active and "primary" or "ghost")
        end
        local submitX = x + innerW - submitW
        self.claimSubmitBtn = mkBtn(submitX, cy, submitW, "Submit claim", LasciviousFactionsSystemPanel.onClaimSubmit, "primary", "ic_claims")
        self.claimClearBtn = mkBtn(submitX - BTN_GAP - clearW, cy, clearW, "Clear", LasciviousFactionsSystemPanel.onClaimClear, "ghost")
    else
        -- Two stacked pairs of equal halves.
        local halfW = math.floor((innerW - BTN_GAP) / 2)
        local rightX = x + innerW - halfW
        self.claimDrawBtn = mkBtn(x, cy, halfW, "Draw claim", LasciviousFactionsSystemPanel.onClaimDrawToggle, "ghost", "ic_claim", drawTip)
        self.claimEraseBtn = mkBtn(rightX, cy, halfW, "Erase", LasciviousFactionsSystemPanel.onClaimEraseToggle, "ghost", "ic_unclaim", eraseTip)
        self.claimClearBtn = mkBtn(x, row2Y, halfW, "Clear", LasciviousFactionsSystemPanel.onClaimClear, "ghost")
        self.claimSubmitBtn = mkBtn(rightX, row2Y, halfW, "Submit claim", LasciviousFactionsSystemPanel.onClaimSubmit, "primary", "ic_claims")
        row2Y = row2Y + BTN_H + ROW_GAP
    end
    self.claimSubmitBtn:setEnable(false)
    self.claimClearBtn:setEnable(false)

    -- Unclaim | Set respawn here -- only in the narrow layout. With the area column
    -- up, both already live at the bottom of it.
    if not showColumn then
        local halfW = math.floor((innerW - BTN_GAP) / 2)
        mkBtn(x, row2Y, halfW, "Unclaim", LasciviousFactionsSystemPanel.onUnclaimClick, "danger", "ic_unclaim")

        local respawnBtn = mkBtn(x + innerW - halfW, row2Y, halfW, "Set respawn here", LasciviousFactionsSystemPanel.onSetRespawnClick, "ghost", "ic_respawn")
        -- Advisory only (server re-checks setRespawn -> respawn_must_be_in_claim).
        local inClaim = FF.pointInClaim(faction, math.floor(getPlayer():getX()), math.floor(getPlayer():getY()))
        respawnBtn:setEnable(inClaim)
        if not inClaim then
            respawnBtn.tooltip = FF.tr("Stand inside your claim to set the respawn point")
        end
        row2Y = row2Y + BTN_H + ROW_GAP
    end

    -- Shop-claim row: the button, then an inline explainer filling the rest of the
    -- row. The explainer is the discoverability half of this -- a button nobody
    -- understands is barely better than the buried dialog it replaces -- so it states
    -- the one thing that surprises people: a shop does NOT have to touch your base.
    local usedPublic, maxPublic = self.claimMap:publicAreaCount()
    local shopBtn = mkBtn(x, row2Y, shopW, SHOP_LABEL,
        LasciviousFactionsSystemPanel.onShopClaimToggle, "primary", "ic_claims")
    shopBtn.tint = UI.publicClaimColor
    self.claimShopBtn = shopBtn

    if maxPublic <= 0 then
        shopBtn:setEnable(false)
        shopBtn.tooltip = FF.tr("Public areas are disabled on this server (MaxPublicClaimAreas = 0).")
    elseif usedPublic >= maxPublic then
        shopBtn:setEnable(false)
        shopBtn.tooltip = FF.text("UI_LFS_PublicAreaFull",
            "You already have %d of %d public areas. Remove one to make another.",
            usedPublic, maxPublic)
    else
        shopBtn.tooltip = FF.text("UI_LFS_PublicAreaTooltip",
            "Drag a box anywhere on the map to open a public area. Unlike a base claim it does NOT have to sit next to your other land, and it can border a rival's territory. Anyone can walk in; use the area's access badge to choose exactly what they may do there.")
    end

    local noteX = x + shopW + BTN_GAP
    local noteW = innerW - shopW - BTN_GAP
    if noteW >= 120 then
        local note = FF.text("UI_LFS_PublicAreaUsage",
            "Public area -- may sit anywhere. %d / %d used.", usedPublic, maxPublic)
        self:addLabel(noteX, row2Y + math.floor((BTN_H - UI.fh(UI.font.small)) / 2),
            UI.fit(UI.font.small, note, noteW), UI.color.dim, UI.font.small)
    end
end

-- Faction upgrades ("Aprimoramentos"): milestone/points header, then one card per
-- FF.UPGRADE_TYPES entry with its level bar, description and allocate button.
-- Infrastructure + UI only, per the design brief -- no upgrade actually DOES
-- anything yet, hence the "(em desenvolvimento)" badge on every card. Only the
-- owner may allocate (server-enforced via ownerFaction, same as every other
-- owner-only action); everyone else sees the same cards with the button disabled,
-- since the roadmap itself is useful to a regular member too.
function LasciviousFactionsSystemPanel:populateUpgrades()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end
    FF.ensureUpgrades(faction)
    local u = faction.upgrades
    local c = UI.color
    local isOwner = faction.owner == username
    local active = FF.upgradesActive(faction)

    local x = UI.pad
    local headerY = self:addHeader(name, faction, username)

    -- Whole-tab scroll pane (same idiom as Overview/Help/Settings): five content
    -- cards plus the header tiles will not all fit a short window.
    local scroll = ISPanel:new(0, headerY, self.content:getWidth(), self.content:getHeight() - headerY)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    self.content:addChild(scroll)
    self.activeScroll = scroll

    local innerW = self.content:getWidth() - 2 * UI.pad - 16   -- leave room for the scrollbar
    local y = UI.pad
    local pad = 12
    local EH = UI.rowH(UI.font.body)

    -- Header tiles: power / next milestone (progress bar to the next threshold),
    -- and points currently available to spend. Same FFStat tile the Overview
    -- headline row uses, for visual consistency across tabs.
    local score = FF.factionScore(faction)
    local nextMilestone = FF.upgradeMilestoneAt(u.milestonesClaimed + 1)
    local prevMilestone = (u.milestonesClaimed > 0) and FF.upgradeMilestoneAt(u.milestonesClaimed) or 0
    local span = math.max(1, nextMilestone - prevMilestone)
    local tiles = {
        { kicker = FF.text("UI_LFS_UpgradePowerKicker", "PODER DA FACÇÃO"), value = shortScore(score),
          valueSuffix = FF.text("UI_LFS_UpgradeNextMilestoneSuffix", "/ %d próximo marco",
              math.floor(nextMilestone + 0.5)),
          fraction = (score - prevMilestone) / span },
        { kicker = FF.text("UI_LFS_UpgradePointsKicker", "PONTOS DE APRIMORAMENTO"), value = tostring(u.points),
          sub = FF.text("UI_LFS_UpgradeMilestonesClaimedSub", "%d marcos alcançados", u.milestonesClaimed) },
    }
    local tileW = math.floor((innerW - (#tiles - 1) * 10) / #tiles)
    local tileH = 0
    for i, t in ipairs(tiles) do
        local tile = FFStat:new(x + (i - 1) * (tileW + 10), y, tileW, t)
        tile:initialise(); tile:instantiate(); scroll:addChild(tile)
        tileH = math.max(tileH, tile:getHeight())
    end
    y = y + tileH + 10

    if not active then
        local note = Notice:new(x, y, innerW,
            FF.text("UI_LFS_UpgradeInactiveNotice",
                "Inativo: sua facção precisa de território claimado para que os aprimoramentos funcionem."),
            UI.color.warn, "ic_flame")
        note:initialise(); scroll:addChild(note)
        y = y + note:getHeight() + 10
    end

    -- Rebuilt from scratch 2026-08-21 -- the previous fixed-uniform-height
    -- version (every card reserving the same worst-case space) STILL showed a
    -- card overlapping/effectively disappearing in live testing, and no
    -- concrete root cause was ever confirmed by re-reading the layout math
    -- (which was, and remains, arithmetically sound as far as static
    -- inspection can tell). Per explicit instruction ("mude completamente a
    -- forma de criação dos cards... algo análogo e fixo"), rather than adding
    -- another unverified patch, this changes TWO things at once, either of
    -- which alone would already remove a real suspect:
    --
    -- 1) The button moves onto the TITLE row (top-right, beside the upgrade
    --    name) instead of its own row at the card's bottom -- explicit ask,
    --    and it also means the card is once again sized to ONLY the height
    --    its own text needs (no more shared worst-case reservation), also
    --    explicitly requested ("fazer o tamanho ser apenas o tamanho
    --    necessário para caber o texto em si").
    -- 2) The next card's Y position is now advanced using a height computed
    --    ENTIRELY IN LUA (UI.cardH(cy), the exact same formula
    --    FFCard:setContentHeight itself uses internally) captured from that
    --    ONE call's own return value -- never a SEPARATE later call to
    --    card:getHeight(). The previous version called setContentHeight and
    --    THEN queried getHeight() on its own line afterward; if the widget's
    --    Java-side height ever failed to reflect a Lua setHeight() call
    --    synchronously for some card (never proven, but never ruled out
    --    either, and consistent with a card silently rendering collapsed/
    --    "swallowed" rather than merely mis-sized), that gap is exactly where
    --    it would live. Reading the value straight off the setter's own
    --    return removes that gap entirely regardless of whether it was ever
    --    the actual cause.
    -- Built cards, in order -- kept around so the verification pass below can
    -- re-check every ACTUAL on-widget position/height once everything
    -- exists, not just trust the running `y` this loop accumulates while
    -- building. See that pass's own comment for why.
    local cards = {}

    for _, def in ipairs(FF.UPGRADE_TYPES) do
        local level = FF.upgradeLevel(faction, def.key)
        local maxed = level >= def.maxLevel
        local label = FF.text(def.labelKey, def.labelFallback)
        local tier = def.descTiers[FF.upgradeTier(level)]
        local desc = FF.text(tier.key, tier.fallback)
        local technical = FF.text(def.technicalKey, def.technicalFallback)

        local card = FFCard:new(x, y, innerW, 0, string.upper(label))
        card:initialise(); card:instantiate()

        local btnLabel, disabledNeutral, tooltip
        if maxed then
            btnLabel = FF.text("UI_LFS_UpgradeMaxed", "Nível máximo")
            disabledNeutral = true
        else
            btnLabel = FF.text("UI_LFS_UpgradeButton", "Aprimorar (1 ponto)")
            if not isOwner then
                tooltip = FF.text("UI_LFS_UpgradeNotOwnerTooltip",
                    "Apenas o líder da facção pode alocar pontos de aprimoramento.")
                disabledNeutral = true
            elseif (u.points or 0) <= 0 then
                tooltip = FF.text("UI_LFS_UpgradeNoPointsTooltip",
                    "Sua facção não possui pontos de aprimoramento disponíveis.")
                disabledNeutral = true
            end
        end
        local canAllocate = isOwner and not maxed and (u.points or 0) > 0

        -- Title row: button top-right, roughly level with the card's own
        -- title text (drawn by FFCard itself at a fixed y=8 -- see
        -- FFCard:prerender, LFS_UI.lua). btnY nudged down a little from the
        -- very top per explicit ask ("uma margem em relação ao topo") --
        -- deliberately does NOT change the math.max(...) below, so the level
        -- text still only gets pushed down if this ever genuinely needs the
        -- room (it doesn't, at this value -- there was slack already).
        local btnW = UI.buttonWidth(btnLabel, false, EH)
        local btnY = 8
        local btn = FFButton:new(innerW - pad - btnW, btnY, btnW, EH, btnLabel,
            self, LasciviousFactionsSystemPanel.onAllocateUpgrade, "primary")
        btn.upgradeKey = def.key
        btn.disabledNeutral = disabledNeutral
        btn:initialise(); btn:instantiate()
        btn:setEnable(canAllocate)
        btn.tooltip = tooltip
        card:addChild(btn)

        local cy = math.max(card:contentTop(), btnY + EH + 6)

        local levelText = FF.text("UI_LFS_UpgradeLevelLabel", "Nível %d / %d", level, def.maxLevel)
        cardText(card, pad, cy, levelText, c.text2)
        cy = cy + UI.lineH(UI.font.body) + 3

        local bar = FFBar:new(pad, cy, innerW - 2 * pad, 8)
        bar:initialise()
        bar.fraction = level / def.maxLevel
        -- Fixed two-state colour, not UI.barColor's default capacity gradient (green
        -- -> amber -> red as fraction climbs): that reads as "more level = more
        -- danger", backwards for a progress bar where more is good. Green while
        -- there's still levels to buy, accent purple only once maxed.
        bar.color = maxed and c.accent or c.good
        card:addChild(bar)
        cy = cy + 8 + 8

        for _, line in ipairs(wrapText(desc, UI.font.small, innerW - 2 * pad)) do
            cardText(card, pad, cy, line, c.dim, UI.font.small)
            cy = cy + UI.lineH(UI.font.small)
        end
        -- Technical paragraph: what the upgrade actually does, in concrete
        -- numbers, right below the creative one -- explicit ask ("uma
        -- descrição entre parênteses do que o aprimoramento faz
        -- tecnicamente"). Static per upgrade, not tiered like the creative
        -- text above it -- it is describing the mechanic as a whole, not the
        -- faction's current standing in it.
        for _, line in ipairs(wrapText(technical, UI.font.small, innerW - 2 * pad)) do
            cardText(card, pad, cy, line, c.faint, UI.font.small)
            cy = cy + UI.lineH(UI.font.small)
        end
        cy = cy + 10

        local cardH = card:setContentHeight(cy)
        scroll:addChild(card)
        cards[#cards + 1] = card
        y = y + cardH + 8
    end

    -- Verification/correction pass, explicit ask: don't just trust the `y`
    -- this loop accumulated while building -- after every card exists, walk
    -- them pairwise and check the REAL gap between each one's actual
    -- getY()/getHeight() and the next card's actual getY(). Fix any card
    -- that isn't sitting exactly CARD_GAP below the previous one's real
    -- bottom edge, whichever direction the drift went (overlapping OR
    -- leaving extra slack) -- this catches a wrong position regardless of
    -- WHY the build-time arithmetic that placed it there might have drifted,
    -- since it works off what the widgets report now, not off values
    -- accumulated mid-build.
    local CARD_GAP = 8
    for i = 2, #cards do
        local prevCard, curCard = cards[i - 1], cards[i]
        local expectedY = prevCard:getY() + prevCard:getHeight() + CARD_GAP
        if math.floor(curCard:getY() + 0.5) ~= math.floor(expectedY + 0.5) then
            curCard:setY(expectedY)
        end
    end

    -- Scroll height from the LAST card's real, post-correction bottom edge --
    -- not the `y` the build loop accumulated, which is exactly the value the
    -- pass above just finished treating as untrustworthy.
    local lastCard = cards[#cards]
    local scrollBottom = lastCard and (lastCard:getY() + lastCard:getHeight() + CARD_GAP) or y
    scroll:setScrollHeight(scrollBottom)
end

function LasciviousFactionsSystemPanel:onAllocateUpgrade(button)
    local key = button and button.upgradeKey
    if not key then return end
    send("allocateUpgradePoint", { upgrade = key })
end

-- ---------------------------------------------------------------------------
-- Veículos: every vehicle currently detected inside the faction's own
-- territory (FF.factionVehicles, LFS_VehiclePanel.lua -- walks every loaded
-- vehicle, not just ones near the viewing player, since a faction needs to
-- see ALL of its territory's vehicles here, not just whichever happen to be
-- nearby). PROTEGER makes a vehicle eligible for the Oficina upgrade's
-- auto-repair (server-confirmed after a 1-game-hour delay, see
-- LFS_VehicleGuard.lua); TRANCAR blocks entry/towing by non-members,
-- immediately. Both are server-authoritative -- these buttons only ever
-- request the change, never apply it locally.
--
-- Deliberately excluded from LIVE_REFRESH_SECTIONS, same reasoning as
-- "claims": each row holds a real embedded 3D scene widget
-- (FF_VehicleScene), and recreating those on every live-refresh poll (as
-- opposed to only when the player actually navigates here or takes an
-- action) would be real, avoidable Java-side scene churn -- see
-- LFS_VehiclePanel.lua's own comment on FF_VehicleScene for why reuse
-- matters. The tradeoff: the pending-protection countdown is a snapshot at
-- populate time, not a live tick -- acceptable, matches how the claim map
-- already behaves under the same exclusion.
-- ---------------------------------------------------------------------------
-- CORRECTION: an earlier pass doubled this box (110x90 -> 220x170) to make
-- the vehicle look bigger -- wrong lever. The 3D camera's field of view is
-- NOT auto-scaled to the viewport size, so a bigger box just showed more
-- empty dark space around the same small-looking model (confirmed by
-- screenshot: huge card, tiny car). Reverted close to the original box size;
-- the actual fix -- pulling the camera closer -- lives in FF_VehicleScene's
-- own ZOOM_BOOST (LFS_VehiclePanel.lua), which multiplies the shop's proven
-- footprint-based zoom formula instead of touching viewport pixels.
local VEHICLE_PREVIEW_W, VEHICLE_PREVIEW_H = 130, 105

function LasciviousFactionsSystemPanel:populateVehicles()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end
    FF.ensureVehicleGuard(faction)

    -- Fresh every rebuild: the labels a stale entry here would point at get
    -- destroyed by self.content:clearChildren() (called by showSection just
    -- before this runs), so old references would be dangling. Repopulated
    -- below by addVehicleRow for each currently-pending row; :prerender()'s
    -- in-place countdown update reads this every frame.
    self.vehiclePendingLabels = {}

    local c = UI.color
    local x = UI.pad
    local headerY = self:addHeader(name, faction, username)

    local scroll = ISPanel:new(0, headerY, self.content:getWidth(), self.content:getHeight() - headerY)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    self.content:addChild(scroll)
    self.activeScroll = scroll

    local innerW = self.content:getWidth() - 2 * UI.pad - 16
    local y = UI.pad
    local pad = 12

    local opts = FF.getOptions()
    local limit = FF.vehicleProtectionLimit(faction, opts)
    local used = FF.vehicleProtectionCount(faction)
    local info = Notice:new(x, y, innerW,
        FF.text("UI_LFS_VehiclesInfo", "Vagas de proteção usadas: %s / %s.", tostring(used), tostring(limit)),
        c.dim, nil)
    info:initialise(); scroll:addChild(info)
    y = y + info:getHeight() + 10

    -- Every loaded vehicle, regardless of territory -- gives a PROTECTED row
    -- its live 3D preview/name whenever it's loaded at all, even if it's not
    -- currently standing inside the claim (drove out for a supply run, e.g.)
    -- -- protection never depended on being in-territory to begin with, only
    -- repair eligibility does (LFS_Server.lua). Using the territory-filtered
    -- list here was the earlier bug: a loaded, visible, protected vehicle one
    -- tile past the claim edge showed "fora de alcance" for no good reason.
    local liveById = {}
    for _, v in ipairs(FF.allLoadedVehicles()) do liveById[v:getId()] = v end

    -- Territory-filtered separately -- this one legitimately needs it, since
    -- it's specifically "new candidates found inside MY territory".
    local liveVehicles = FF.factionVehicles(name)

    -- Protected vehicles are ALWAYS listed here, regardless of whether they
    -- are currently in range or even loaded right now -- protection is a
    -- persistent faction decision, not something that should vanish from the
    -- tab just because the vehicle drove off or its chunk unloaded (explicit
    -- user requirement). Sorted by name since the registry is a plain dict
    -- with no defined pairs() order.
    local protectedIds = {}
    for id in pairs(faction.vehicles.protected) do protectedIds[#protectedIds + 1] = id end
    table.sort(protectedIds, function(a, b)
        local ea, eb = faction.vehicles.protected[a], faction.vehicles.protected[b]
        return tostring(ea and ea.name) < tostring(eb and eb.name)
    end)

    -- Detected-in-territory but not yet protected -- these only ever show
    -- while actually in range; there is nothing persistent to remember about
    -- them until PROTEGER is used.
    local unprotected = {}
    for _, v in ipairs(liveVehicles) do
        if not faction.vehicles.protected[v:getId()] then unprotected[#unprotected + 1] = v end
    end

    if #protectedIds == 0 and #unprotected == 0 then
        local empty = Notice:new(x, y, innerW,
            FF.text("UI_LFS_VehiclesNone", "Nenhum veículo protegido, e nenhum detectado no território agora."),
            c.dim, nil)
        empty:initialise(); scroll:addChild(empty)
        y = y + empty:getHeight() + 10
    end

    if #protectedIds > 0 then
        cardText(scroll, x, y, FF.text("UI_LFS_VehiclesProtectedHeader", "PROTEGIDOS"), c.accent, UI.font.small)
        y = y + UI.lineH(UI.font.small) + 6
        for _, id in ipairs(protectedIds) do
            y = self:addVehicleRow(scroll, liveById[id], faction, x, y, innerW, pad, id)
        end
    end

    if #unprotected > 0 then
        cardText(scroll, x, y, FF.text("UI_LFS_VehiclesDetectedHeader", "DETECTADOS NO TERRITÓRIO"), c.accent, UI.font.small)
        y = y + UI.lineH(UI.font.small) + 6
        for _, v in ipairs(unprotected) do
            y = self:addVehicleRow(scroll, v, faction, x, y, innerW, pad, v:getId())
        end
    end

    scroll:setScrollHeight(y)
end

-- PT-BR display name for a vehicle we don't currently have a live object
-- for -- mirrors the core of vanilla's own ISVehicleMenu.getVehicleDisplayName
-- (skipping its "Burnt" special case, not worth replicating for this
-- fallback-only path) using the raw script name LFS_Server.lua stored at
-- protect time (see vehicleRawName in LFS_Server.lua).
local function fallbackVehicleName(rawName)
    if rawName then
        local ok, text = pcall(getText, "IGUI_VehicleName" .. rawName)
        if ok and text and text ~= ("IGUI_VehicleName" .. rawName) then return text end
    end
    return FF.text("UI_LFS_VehicleUnknownName", "Veículo")
end

-- One vehicle's row: FFCard titled with its display name, a 3D preview at
-- the content area's left edge (or an "out of range" note if `vehicle` is
-- nil -- see populateVehicles), and status lines + the two action buttons to
-- its right. `id` is passed explicitly since a protected-but-unloaded row
-- has no live object to read it from.
function LasciviousFactionsSystemPanel:addVehicleRow(scroll, vehicle, faction, x, y, innerW, pad, id)
    local c = UI.color
    local EH = UI.rowH(UI.font.body)
    local protectedEntry = faction.vehicles.protected[id]
    -- Role-gated (protectVehicles permission, on by default for Líder/Oficial
    -- -- see FF.defaultRoles) -- purely a UI convenience like every other
    -- client-side gate here; Handlers.requestProtectVehicle/unprotectVehicle/
    -- toggleLockVehicle (LFS_Server.lua) enforce the real check.
    local username = getPlayer() and getPlayer():getUsername()
    local canManage = username ~= nil and FF.roleCan(faction, username, "protectVehicles")

    local displayName
    if vehicle then
        local okName, n = pcall(ISVehicleMenu.getVehicleDisplayName, vehicle)
        if okName and n then displayName = n end
    end
    if not displayName then displayName = fallbackVehicleName(protectedEntry and protectedEntry.name) end

    local card = FFCard:new(x, y, innerW, 0, displayName)
    card:initialise(); card:instantiate()
    local cy = card:contentTop()

    if vehicle then
        local scene = FF_VehicleScene:new(pad, cy, VEHICLE_PREVIEW_W, VEHICLE_PREVIEW_H)
        scene:initialise(); scene:instantiate()
        card:addChild(scene)
        scene:setupOnce()
        local okType, fullType = pcall(function() return vehicle:getScript():getFullName() end)
        if okType then scene:showVehicleType(fullType) end
    else
        -- No live object to preview -- reserve the same footprint so every
        -- row lines up, just with a short explanation instead of a 3D scene
        -- (also avoids creating a scene widget with nothing to show).
        local oorMsg = FF.text("UI_LFS_VehicleOutOfRange", "Fora de alcance -- não carregado no momento")
        local oy = cy + math.floor(VEHICLE_PREVIEW_H / 2) - UI.lineH(UI.font.small)
        for _, line in ipairs(wrapText(oorMsg, UI.font.small, VEHICLE_PREVIEW_W)) do
            cardText(card, pad, oy, line, c.dim, UI.font.small)
            oy = oy + UI.lineH(UI.font.small)
        end
    end

    local rx = pad + VEHICLE_PREVIEW_W + pad
    local rw = innerW - rx - pad

    local confirmed = protectedEntry ~= nil and protectedEntry.protectedAt ~= nil
    local pending = protectedEntry ~= nil and not confirmed
    local locked = faction.vehicles.locked[id] == true

    -- Minutes remaining for the status line below (:prerender() recomputes
    -- this same figure independently every frame to tick the label in
    -- place -- see the in-place-update block's own comment). Ceil so "less
    -- than a minute left" still shows 1, never a misleading 0.
    local pendingMinutes
    if pending then
        local nowHours = getGameTime():getWorldAgeHours()
        local remaining = math.max(0, FF.VEHICLE_PROTECT_CONFIRM_HOURS
            - (nowHours - (protectedEntry.requestedAt or nowHours)))
        pendingMinutes = math.max(1, math.ceil(remaining * 60))
    end

    -- Right column (2 status lines + gap + 1 button row) is much shorter than
    -- the preview -- vertically centred against it instead of pinned to the
    -- top, so a big empty gap doesn't form under short text next to a tall
    -- viewport.
    local rightColH = 2 * UI.lineH(UI.font.small) + 8 + EH
    local ry = cy + math.max(0, math.floor((VEHICLE_PREVIEW_H - rightColH) / 2))

    local statusText, statusColor
    if not protectedEntry then
        statusText, statusColor = FF.text("UI_LFS_VehicleStatusUnprotected", "Não protegido"), c.dim
    elseif pending then
        -- "min de jogo", explicitly -- not real minutes. The countdown is
        -- measured against getGameTime():getWorldAgeHours() (matches the
        -- user's own original spec: "esperar 1 hora DO JOGO"), which can
        -- take noticeably longer or shorter in real time depending on the
        -- server's day-length sandbox setting -- spelling out the unit here
        -- is what stops "it said 1 min but took way longer" from reading as
        -- a bug when it's really just a different clock than expected.
        statusText = FF.text("UI_LFS_VehicleStatusPending",
            "Proteção pendente -- confirma em %s min de jogo", tostring(pendingMinutes))
        statusColor = c.accentText
    else
        statusText, statusColor = FF.text("UI_LFS_VehicleStatusProtected", "Protegido"), c.ok
    end
    local statusLabel = cardText(card, rx, ry, UI.fit(UI.font.small, statusText, rw), statusColor, UI.font.small)
    -- Registered so :prerender() can tick this ONE label's text in place
    -- every frame (ISLabel:setName()) without rebuilding the row -- see that
    -- block's own comment. Only pending rows need it; confirmed/unprotected
    -- status text never changes on its own.
    if pending then self.vehiclePendingLabels[id] = statusLabel end
    ry = ry + UI.lineH(UI.font.small)

    local lockText = locked and FF.text("UI_LFS_VehicleStatusLocked", "Trancado")
        or FF.text("UI_LFS_VehicleStatusUnlocked", "Destrancado")
    cardText(card, rx, ry, lockText, locked and c.warn or c.dim, UI.font.small)
    ry = ry + UI.lineH(UI.font.small) + 8

    -- Static while pending, deliberately no live number here -- the ticking
    -- countdown lives in the status line above (which DOES update in place
    -- every frame); duplicating it onto the button's own label would need a
    -- second, unproven in-place update path (FFButton's title isn't a plain
    -- ISLabel the way cardText's lines are), for no real benefit.
    local protectBtnLabel
    if not canManage then
        protectBtnLabel = FF.text("UI_LFS_VehicleNoPermission", "Sem permissão")
    elseif pending then
        protectBtnLabel = FF.text("UI_LFS_VehicleProtectPending", "Aguardando confirmação...")
    elseif confirmed then
        protectBtnLabel = FF.text("UI_LFS_VehicleUnprotectButton", "Desproteger")
    else
        protectBtnLabel = FF.text("UI_LFS_VehicleProtectButton", "Proteger")
    end
    local protectBtnW = UI.buttonWidth(protectBtnLabel, false, EH)
    local protectBtn = FFButton:new(rx, ry, protectBtnW, EH, protectBtnLabel,
        self, LasciviousFactionsSystemPanel.onToggleProtectVehicle, confirmed and "ghost" or "primary")
    protectBtn.vehicleId = id
    protectBtn.vehicleProtected = protectedEntry ~= nil
    protectBtn.disabledNeutral = pending or not canManage
    protectBtn:initialise(); protectBtn:instantiate()
    protectBtn:setEnable(canManage and not pending)
    card:addChild(protectBtn)

    -- TRANCAR only exists for a CONFIRMED-protected vehicle -- explicit
    -- design requirement: locking must never be available for a vehicle the
    -- faction hasn't already gone through the protection flow (and its
    -- anti-abuse re-check) for. Server-side enforces this too (see
    -- Handlers.toggleLockVehicle) -- this client-side gate is purely so the
    -- button reads clearly, not the actual security boundary. Locking ALSO
    -- needs a live vehicle (the server has to read its current position);
    -- unlocking never does (see Handlers.toggleLockVehicle's else branch),
    -- so an already-locked-but-unloaded row can still be unlocked. Gated on
    -- the SAME protectVehicles permission as PROTEGER for both lock AND
    -- unlock -- a member without the permission shouldn't be able to undo a
    -- lock either, or the permission would be meaningless.
    local canLock = canManage and confirmed and vehicle ~= nil
    local lockBtnLabel
    if not canManage then
        lockBtnLabel = FF.text("UI_LFS_VehicleNoPermission", "Sem permissão")
    elseif not confirmed then
        lockBtnLabel = FF.text("UI_LFS_VehicleLockNeedsProtect", "Proteja primeiro")
    elseif locked then
        lockBtnLabel = FF.text("UI_LFS_VehicleUnlockButton", "Destrancar")
    elseif not vehicle then
        lockBtnLabel = FF.text("UI_LFS_VehicleLockNotLoaded", "Não carregado")
    else
        lockBtnLabel = FF.text("UI_LFS_VehicleLockButton", "Trancar")
    end
    local lockBtnW = UI.buttonWidth(lockBtnLabel, false, EH)
    local lockBtn = FFButton:new(rx + protectBtnW + 8, ry, lockBtnW, EH, lockBtnLabel,
        self, LasciviousFactionsSystemPanel.onToggleLockVehicle, locked and "ghost" or "primary")
    lockBtn.vehicleId = id
    lockBtn.vehicleLocked = locked
    local lockEnabled = canManage and (canLock or locked)
    lockBtn.disabledNeutral = not lockEnabled
    lockBtn:initialise(); lockBtn:instantiate()
    lockBtn:setEnable(lockEnabled)
    card:addChild(lockBtn)
    ry = ry + EH + pad

    local contentBottom = math.max(cy + VEHICLE_PREVIEW_H + pad, ry)
    card:setContentHeight(contentBottom)
    scroll:addChild(card)
    return y + card:getHeight() + 10
end

-- Deliberately does NOT rebuild the section itself (no showSection call) --
-- the earlier version did, and rebuilding the whole "vehicles" tab
-- synchronously from inside its own button's onMouseUp is what caused the
-- reported "PROTEGER needs two clicks" bug (the just-clicked button gets
-- torn down and recreated mid-event, confusing the next click's
-- hit-testing). "vehicles" is now in LIVE_REFRESH_SECTIONS, so
-- liveRefreshFingerprint picks up the server's reply and rebuilds cleanly
-- from :prerender() instead, one frame later -- outside the click handler's
-- own call stack. It also would have shown stale data anyway: the local
-- send() here has no effect on faction.vehicles until the server actually
-- processes it and syncs back, so an immediate local rebuild was never truly
-- "instant" feedback to begin with.
function LasciviousFactionsSystemPanel:onToggleProtectVehicle(button)
    if button.vehicleProtected then
        send("unprotectVehicle", { vehicleId = button.vehicleId })
    else
        send("requestProtectVehicle", { vehicleId = button.vehicleId })
    end
end

function LasciviousFactionsSystemPanel:onToggleLockVehicle(button)
    send("toggleLockVehicle", { vehicleId = button.vehicleId, locked = not button.vehicleLocked })
end

-- Debug tools: gated on FF.getOptions().debugToolsEnabled (true singleplayer +
-- the Debug sandbox flag, see LFS_Shared.lua) -- test actions for the mod
-- author's own testing, never available in real MP, not part of normal play.
-- The tab itself is already filtered out of the sidebar when the gate is off
-- (see :visibleSections); this top guard only covers the tab staying open
-- across a live sandbox toggle mid-session. New debug actions get their own
-- card here as they're added -- for now just the one, per the design brief.
function LasciviousFactionsSystemPanel:populateDebug()
    local opts = FF.getOptions()
    if not opts.debugToolsEnabled then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14,
            FF.text("UI_LFS_DebugUnavailable", "As ferramentas de debug estão desativadas."),
            UI.color.text, UI.font.title)
        return
    end

    local valid = false
    for _, t in ipairs(DEBUG_SUBTABS) do if t.key == self.debugSubTab then valid = true end end
    if not valid then self.debugSubTab = DEBUG_SUBTABS[1].key end

    self:addLabel(UI.pad, 12, "Debug", UI.color.text, UI.font.title)
    local strip = FFSubTabs:new(UI.pad, 12 + UI.fh(UI.font.title) + 10, DEBUG_SUBTABS,
        self.debugSubTab, self, LasciviousFactionsSystemPanel.onDebugSubTab)
    strip:initialise(); strip:instantiate()
    self.content:addChild(strip)

    self.sectionTop = strip:getY() + strip:getHeight() + 6
    self.suppressHeader = true

    if self.debugSubTab == "vehicles" then self:populateDebugVehicles()
    elseif self.debugSubTab == "hunter" then self:populateDebugHunter()
    else self:populateDebugWellbeing() end
end

function LasciviousFactionsSystemPanel:onDebugSubTab(key)
    self.debugSubTab = key
    self:showSection("debug")
end

-- ---------------------------------------------------------------------------
-- Debug > Bem-estar: faction power test button + the wellbeing snapshot tools
-- (unchanged content, just moved under the new sub-tab strip).
-- ---------------------------------------------------------------------------
function LasciviousFactionsSystemPanel:populateDebugWellbeing()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end

    local c = UI.color
    local x = UI.pad
    local headerY = self:addHeader(name, faction, username)

    local scroll = ISPanel:new(0, headerY, self.content:getWidth(), self.content:getHeight() - headerY)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    self.content:addChild(scroll)
    self.activeScroll = scroll

    local innerW = self.content:getWidth() - 2 * UI.pad - 16
    local y = UI.pad
    local pad = 12
    local EH = UI.rowH(UI.font.body)

    local note = Notice:new(x, y, innerW,
        FF.text("UI_LFS_DebugWarning",
            "Ferramentas de teste -- alteram dados reais da facção. Use com cuidado."),
        UI.color.warn, "ic_flame")
    note:initialise(); scroll:addChild(note)
    y = y + note:getHeight() + 10

    local card = FFCard:new(x, y, innerW, 0, FF.text("UI_LFS_DebugPowerCardTitle", "PODER DA FACÇÃO"))
    card:initialise(); card:instantiate()
    local cy = card:contentTop()

    local powerText = FF.text("UI_LFS_DebugCurrentPower", "Poder atual: %s", shortScore(FF.factionScore(faction)))
    cardText(card, pad, cy, powerText, c.text2)
    cy = cy + UI.lineH(UI.font.body) + 8

    local btnLabel = FF.text("UI_LFS_DebugAddPowerButton", "+100 de poder")
    local btnW = UI.buttonWidth(btnLabel, false, EH)
    local btn = FFButton:new(pad, cy, btnW, EH, btnLabel, self, LasciviousFactionsSystemPanel.onDebugAddPower, "primary")
    btn:initialise(); btn:instantiate(); card:addChild(btn)
    cy = cy + EH + pad

    card:setContentHeight(cy)
    scroll:addChild(card)
    y = y + card:getHeight() + 10

    -- Bem-estar snapshot: visualises what territoryEffectTick (LFS_Territory.lua)
    -- is actually doing, instead of guessing whether a rate matters from firing
    -- counts alone. Two independent capture modes, per feedback that a single
    -- tick's move on a slow stat can round away to "0.0%" and read as "not
    -- working" even when it is: "Capturar snapshot (1h)" starts an ACCUMULATION
    -- that sums every tick's real contribution over a full game hour (see
    -- FF.wellbeingAccumulation), so a slow stat's true size over a meaningful
    -- span is visible; "Capturar último snapshot" just re-reads
    -- FF.lastWellbeingSnapshot, the existing single-tick view, unchanged.
    -- Neither button triggers a fresh application by itself -- the tick only
    -- ever runs once per game-minute, driven by Events.EveryOneMinute.
    --
    -- Only ONE of the two views is ever shown at a time -- self.debugSnapshotView
    -- ("accum" or "last"), flipped by whichever capture button was clicked most
    -- recently -- per feedback that showing both stacked was cluttered and made
    -- it unclear which one a given line of numbers belonged to.
    local snapCard = FFCard:new(x, y, innerW, 0,
        FF.text("UI_LFS_DebugSnapshotCardTitle", "SNAPSHOT DE BEM-ESTAR"))
    snapCard:initialise(); snapCard:instantiate()
    local sy = snapCard:contentTop()

    local accum = FF.wellbeingAccumulation
    local capturing = accum ~= nil and accum.active
    local accumBtnLabel = capturing
        and FF.text("UI_LFS_DebugAccumCapturing", "Capturando...")
        or FF.text("UI_LFS_DebugAccumButton", "Capturar snapshot (1h)")
    local lastBtnLabel = FF.text("UI_LFS_DebugSnapshotButton", "Capturar último snapshot")
    local accumBtnW = UI.buttonWidth(accumBtnLabel, false, EH)
    local lastBtnW = UI.buttonWidth(lastBtnLabel, false, EH)
    local accumBtn = FFButton:new(pad, sy, accumBtnW, EH, accumBtnLabel,
        self, LasciviousFactionsSystemPanel.onDebugCaptureAccumulation, "primary")
    accumBtn.disabledNeutral = capturing
    accumBtn:initialise(); accumBtn:instantiate()
    accumBtn:setEnable(not capturing)
    snapCard:addChild(accumBtn)
    local lastBtn = FFButton:new(pad + accumBtnW + 8, sy, lastBtnW, EH, lastBtnLabel,
        self, LasciviousFactionsSystemPanel.onDebugSnapshot, "ghost")
    lastBtn:initialise(); lastBtn:instantiate(); snapCard:addChild(lastBtn)
    sy = sy + EH + pad

    local view = self.debugSnapshotView or "last"

    if view == "accum" then
        -- --- Accumulated (1 game hour) ---
        cardText(snapCard, pad, sy, FF.text("UI_LFS_DebugAccumSectionTitle", "ACUMULADO (1H DE JOGO)"),
            c.accent, UI.font.small)
        sy = sy + UI.lineH(UI.font.small) + 4

        if not accum then
            cardText(snapCard, pad, sy,
                FF.text("UI_LFS_DebugAccumEmpty", "Nenhuma captura de 1 hora ainda."), c.dim, UI.font.small)
            sy = sy + UI.lineH(UI.font.small) + 8
        elseif accum.active then
            local progress = FF.text("UI_LFS_DebugAccumProgress",
                "Capturando -- faltam %s minuto(s) de jogo (%s com o aprimoramento ativo até agora).",
                tostring(accum.ticksRemaining), tostring(accum.activeTicks or 0))
            for _, line in ipairs(wrapText(progress, UI.font.small, innerW - 2 * pad)) do
                cardText(snapCard, pad, sy, line, c.accentText, UI.font.small)
                sy = sy + UI.lineH(UI.font.small)
            end
            sy = sy + 8
        else
            local finishedAgo = math.max(0, math.floor((getTimestamp() or 0) - (accum.finishedAt or 0)))
            local summary = FF.text("UI_LFS_DebugAccumSummary",
                "%s minuto(s) com o aprimoramento ativo de %s -- concluído há %s segundo(s)",
                tostring(accum.activeTicks or 0), tostring(accum.ticksTotal), tostring(finishedAgo))
            cardText(snapCard, pad, sy, UI.fit(UI.font.small, summary, innerW - 2 * pad), c.accentText, UI.font.small)
            sy = sy + UI.lineH(UI.font.small) + 6

            if #accum.order == 0 then
                cardText(snapCard, pad, sy,
                    FF.text("UI_LFS_DebugAccumNothing", "O aprimoramento não esteve ativo durante essa captura."),
                    c.dim, UI.font.small)
                sy = sy + UI.lineH(UI.font.small)
            else
                for _, key in ipairs(accum.order) do
                    local e = accum.entries[key]
                    local endValue = e.startValue + e.sum
                    local sumStr = (e.sum >= 0 and "+" or "") .. formatSnapshotValue(e.sum, e.max)
                    local line = e.label .. ": " .. formatSnapshotValue(e.startValue, e.max) .. " -> "
                        .. formatSnapshotValue(endValue, e.max) .. "  (" .. sumStr .. ", "
                        .. formatPctChange(e.startValue, endValue) .. ")"
                    cardText(snapCard, pad, sy, UI.fit(UI.font.small, line, innerW - 2 * pad), c.text2, UI.font.small)
                    sy = sy + UI.lineH(UI.font.small)
                end
            end
            sy = sy + 4
        end
    else
        -- --- Last single tick ---
        cardText(snapCard, pad, sy, FF.text("UI_LFS_DebugLastTickSectionTitle", "ÚLTIMO TICK"), c.accent, UI.font.small)
        sy = sy + UI.lineH(UI.font.small) + 4

        local snap = FF.lastWellbeingSnapshot
        if not snap then
            local emptyMsg = FF.text("UI_LFS_DebugSnapshotEmpty",
                "Nenhum snapshot ainda. Entre no território da sua facção com o aprimoramento de Bem-estar acima do nível 0.")
            for _, line in ipairs(wrapText(emptyMsg, UI.font.small, innerW - 2 * pad)) do
                cardText(snapCard, pad, sy, line, c.dim, UI.font.small)
                sy = sy + UI.lineH(UI.font.small)
            end
            sy = sy + 8
        else
            local ageSeconds = math.max(0, math.floor((getTimestamp() or 0) - (snap.at or 0)))
            local summary = FF.text("UI_LFS_DebugSnapshotSummary",
                "Nível %s -- intensidade %s -- há %s segundo(s)",
                tostring(snap.level), string.format("%.2f", snap.intensity or 0), tostring(ageSeconds))
            cardText(snapCard, pad, sy, UI.fit(UI.font.small, summary, innerW - 2 * pad), c.accentText, UI.font.small)
            sy = sy + UI.lineH(UI.font.small) + 6

            for _, entry in ipairs(snap.entries) do
                -- Built with `..` rather than string.format's %s -- see FF.text/getText
                -- comment above; raw accented PT-BR literals broke specifically through
                -- string.format's %s in testing (now moot: labels resolve through
                -- FF.text, proven correct, instead of being raw literals at all).
                local changeText = entry.note or formatPctChange(entry.before, entry.after)
                local line = entry.label .. ": " .. formatSnapshotValue(entry.before, entry.max)
                    .. " -> " .. formatSnapshotValue(entry.after, entry.max) .. " (" .. changeText .. ")"
                cardText(snapCard, pad, sy, UI.fit(UI.font.small, line, innerW - 2 * pad), c.text2, UI.font.small)
                sy = sy + UI.lineH(UI.font.small)
            end
            sy = sy + 4
        end
    end

    snapCard:setContentHeight(sy)
    scroll:addChild(snapCard)
    y = y + snapCard:getHeight() + 10

    scroll:setScrollHeight(y)
end

function LasciviousFactionsSystemPanel:onDebugAddPower(button)
    send("debugAddPower", {})
end

-- Starts a brand-new 1-hour accumulation capture (see FF.wellbeingAccumulation in
-- LFS_Territory.lua). A fresh table every time, not a toggle/reset of the old
-- one, so clicking this again mid-capture restarts cleanly with no leftover
-- totals from the previous window. Also switches the visible section to the
-- accumulated view -- see self.debugSnapshotView above.
function LasciviousFactionsSystemPanel:onDebugCaptureAccumulation(button)
    FF.wellbeingAccumulation = { active = true, ticksTotal = 60, ticksRemaining = 60, activeTicks = 0,
        entries = {}, order = {} }
    self.debugSnapshotView = "accum"
    self:showSection("debug")
end

function LasciviousFactionsSystemPanel:onDebugSnapshot(button)
    self.debugSnapshotView = "last"
    self:showSection("debug")
end

-- ---------------------------------------------------------------------------
-- Debug > Veículos: same idea as the Bem-estar snapshot, applied to the
-- workshop upgrade's vehicle auto-maintenance (server-authoritative, see
-- LFS_Server.lua's workshopMaintTick). "Nearest vehicle" card reads live,
-- already-networked vehicle fields directly (no button needed -- see
-- FF.nearestVehicle in LFS_VehicleDebug.lua); the capture card sums real
-- observed change over a full game hour, since a single poll of a slow rate
-- can round away to nothing.
-- ---------------------------------------------------------------------------
local VEHICLE_SCAN_RADIUS = 20

function LasciviousFactionsSystemPanel:populateDebugVehicles()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end

    local c = UI.color
    local x = UI.pad
    local headerY = self:addHeader(name, faction, username)

    local scroll = ISPanel:new(0, headerY, self.content:getWidth(), self.content:getHeight() - headerY)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    self.content:addChild(scroll)
    self.activeScroll = scroll

    local innerW = self.content:getWidth() - 2 * UI.pad - 16
    local y = UI.pad
    local pad = 12
    local EH = UI.rowH(UI.font.body)

    local note = Notice:new(x, y, innerW,
        FF.text("UI_LFS_DebugVehicleWarning",
            "Leitura ao vivo do veículo mais próximo -- nunca altera nada, apenas mostra o que a manutenção do servidor está vendo."),
        UI.color.warn, "ic_flame")
    note:initialise(); scroll:addChild(note)
    y = y + note:getHeight() + 10

    local vehicle, distSq = FF.nearestVehicle(VEHICLE_SCAN_RADIUS)

    local nearCard = FFCard:new(x, y, innerW, 0,
        FF.text("UI_LFS_DebugVehicleNearestCardTitle", "VEÍCULO MAIS PRÓXIMO"))
    nearCard:initialise(); nearCard:instantiate()
    local ny = nearCard:contentTop()

    if not vehicle then
        cardText(nearCard, pad, ny, FF.text("UI_LFS_DebugVehicleNone",
            "Nenhum veículo num raio de %s quadrado(s).", tostring(VEHICLE_SCAN_RADIUS)), c.dim, UI.font.small)
        ny = ny + UI.lineH(UI.font.small) + 6
    else
        local vfaction, level = FF.workshopLevelAt(vehicle:getX(), vehicle:getY())
        local eligible = level > 0

        local function yesNo(b)
            return b and FF.text("UI_LFS_DebugYes", "sim") or FF.text("UI_LFS_DebugNo", "não")
        end

        local lines = {
            FF.text("UI_LFS_DebugVehicleDistance", "Distância: %s quadrado(s)",
                tostring(math.floor(math.sqrt(distSq or 0)))),
            FF.text("UI_LFS_DebugVehicleTerritory", "Dentro do território: %s",
                vfaction or FF.text("UI_LFS_DebugVehicleOutside", "fora de qualquer território")),
            FF.text("UI_LFS_DebugVehicleLevel", "Nível de Manutenção: %s", tostring(level)),
            FF.text("UI_LFS_DebugVehicleCap", "Teto de reparo: %s%%", tostring(math.min(100, level * 10))),
            FF.text("UI_LFS_DebugVehicleEligible", "Elegível agora: %s", yesNo(eligible)),
        }
        for _, line in ipairs(lines) do
            cardText(nearCard, pad, ny, UI.fit(UI.font.small, line, innerW - 2 * pad), c.text2, UI.font.small)
            ny = ny + UI.lineH(UI.font.small)
        end
        ny = ny + 4

        local state = FF.readVehicleMaintState(vehicle)
        if state.fuel then
            local pctFuel = state.fuelCapacity > 0 and (state.fuel / state.fuelCapacity * 100) or 0
            cardText(nearCard, pad, ny, FF.text("UI_LFS_DebugVehicleFuel",
                "Combustível: %s / %s (%s%%)", formatSnapshotValue(state.fuel), formatSnapshotValue(state.fuelCapacity),
                string.format("%.0f", pctFuel)), c.accentText, UI.font.small)
            ny = ny + UI.lineH(UI.font.small) + 6
        end
        if state.batteryCharge then
            cardText(nearCard, pad, ny, FF.text("UI_LFS_DebugVehicleBattery", "Carga da bateria: %s%%",
                string.format("%.0f", state.batteryCharge * 100)), c.accentText, UI.font.small)
            ny = ny + UI.lineH(UI.font.small) + 6
        end

        cardText(nearCard, pad, ny, FF.text("UI_LFS_DebugVehiclePartsTitle", "PEÇAS INSTALADAS"), c.accent, UI.font.small)
        ny = ny + UI.lineH(UI.font.small) + 4
        if #state.parts == 0 then
            cardText(nearCard, pad, ny, FF.text("UI_LFS_DebugVehicleNoParts", "Nenhuma peça detectada."),
                c.dim, UI.font.small)
            ny = ny + UI.lineH(UI.font.small)
        else
            for _, p in ipairs(state.parts) do
                cardText(nearCard, pad, ny, p.id .. ": " .. tostring(p.condition) .. " / 100", c.text2, UI.font.small)
                ny = ny + UI.lineH(UI.font.small)
            end
        end
        ny = ny + 4
    end

    nearCard:setContentHeight(ny)
    scroll:addChild(nearCard)
    y = y + nearCard:getHeight() + 10

    -- --- Capture card ---
    local accum = FF.vehicleMaintAccumulation
    local capturing = accum ~= nil and accum.active

    local capCard = FFCard:new(x, y, innerW, 0,
        FF.text("UI_LFS_DebugVehicleCaptureCardTitle", "CAPTURA DE PROGRESSO (1H DE JOGO)"))
    capCard:initialise(); capCard:instantiate()
    local cy = capCard:contentTop()

    local capBtnLabel = capturing
        and FF.text("UI_LFS_DebugAccumCapturing", "Capturando...")
        or FF.text("UI_LFS_DebugVehicleCaptureButton", "Capturar progresso (1h)")
    local capBtnW = UI.buttonWidth(capBtnLabel, false, EH)
    local capBtn = FFButton:new(pad, cy, capBtnW, EH, capBtnLabel,
        self, LasciviousFactionsSystemPanel.onDebugCaptureVehicle, "primary")
    capBtn.disabledNeutral = capturing
    capBtn:initialise(); capBtn:instantiate()
    capBtn:setEnable(not capturing and vehicle ~= nil)
    capCard:addChild(capBtn)
    cy = cy + EH + pad

    if not accum then
        local emptyMsg = FF.text("UI_LFS_DebugVehicleCaptureEmpty",
            "Nenhuma captura ainda. Fique perto de um veículo e clique acima.")
        for _, line in ipairs(wrapText(emptyMsg, UI.font.small, innerW - 2 * pad)) do
            cardText(capCard, pad, cy, line, c.dim, UI.font.small)
            cy = cy + UI.lineH(UI.font.small)
        end
        cy = cy + 8
    elseif accum.active then
        local progress = FF.text("UI_LFS_DebugVehicleCaptureProgress",
            "Capturando -- faltam %s minuto(s) de jogo.", tostring(accum.ticksRemaining))
        cardText(capCard, pad, cy, UI.fit(UI.font.small, progress, innerW - 2 * pad), c.accentText, UI.font.small)
        cy = cy + UI.lineH(UI.font.small) + 8
    else
        if accum.lostVehicle then
            local lostMsg = FF.text("UI_LFS_DebugVehicleCaptureLost",
                "O veículo saiu de alcance antes do fim da captura -- mostrando o progresso até então.")
            for _, line in ipairs(wrapText(lostMsg, UI.font.small, innerW - 2 * pad)) do
                cardText(capCard, pad, cy, line, c.warn, UI.font.small)
                cy = cy + UI.lineH(UI.font.small)
            end
        else
            local finishedAgo = math.max(0, math.floor((getTimestamp() or 0) - (accum.finishedAt or 0)))
            cardText(capCard, pad, cy, FF.text("UI_LFS_DebugVehicleCaptureSummary",
                "Captura concluída há %s segundo(s).", tostring(finishedAgo)), c.accentText, UI.font.small)
            cy = cy + UI.lineH(UI.font.small) + 6
        end

        local baseline, last = accum.baseline, accum.last or accum.baseline
        if baseline then
            local changedAny = false
            if baseline.fuel and last.fuel then
                changedAny = changedAny or (last.fuel ~= baseline.fuel)
                local line = FF.text("UI_LFS_DebugVehicleFuel", "Combustível: %s / %s (%s%%)",
                    formatSnapshotValue(last.fuel), formatSnapshotValue(last.fuelCapacity),
                    string.format("%.0f", last.fuelCapacity > 0 and (last.fuel / last.fuelCapacity * 100) or 0))
                cardText(capCard, pad, cy, line .. "  (" .. formatPctChange(baseline.fuel, last.fuel) .. ")",
                    c.text2, UI.font.small)
                cy = cy + UI.lineH(UI.font.small)
            end
            if baseline.batteryCharge and last.batteryCharge then
                changedAny = changedAny or (last.batteryCharge ~= baseline.batteryCharge)
                local line = FF.text("UI_LFS_DebugVehicleBattery", "Carga da bateria: %s%%",
                    string.format("%.0f", last.batteryCharge * 100))
                cardText(capCard, pad, cy,
                    line .. "  (" .. formatPctChange(baseline.batteryCharge, last.batteryCharge) .. ")",
                    c.text2, UI.font.small)
                cy = cy + UI.lineH(UI.font.small)
            end
            -- Match parts by index between baseline and last -- same key the
            -- server tick's repair carry uses, so a part swapped mid-capture
            -- simply shows as "not found in this capture" rather than a wrong pair.
            local lastByIndex = {}
            for _, p in ipairs(last.parts) do lastByIndex[p.index] = p end
            for _, bp in ipairs(baseline.parts) do
                local lp = lastByIndex[bp.index]
                if lp and lp.condition ~= bp.condition then
                    changedAny = true
                    local line = bp.id .. ": " .. tostring(bp.condition) .. " -> " .. tostring(lp.condition)
                        .. " (" .. formatPctChange(bp.condition, lp.condition) .. ")"
                    cardText(capCard, pad, cy, line, c.text2, UI.font.small)
                    cy = cy + UI.lineH(UI.font.small)
                end
            end
            if not changedAny then
                cardText(capCard, pad, cy,
                    FF.text("UI_LFS_DebugVehicleCaptureNothing", "Nenhuma peça, combustível ou bateria mudou durante a captura."),
                    c.dim, UI.font.small)
                cy = cy + UI.lineH(UI.font.small)
            end
        end
        cy = cy + 4
    end

    capCard:setContentHeight(cy)
    scroll:addChild(capCard)
    y = y + capCard:getHeight() + 10

    -- --- Lock self-test ---
    -- The anti-theft guard (LFS_Server.lua's workshopVehicleGuardTick) only
    -- ever acts on players who are NOT members of the locking faction --
    -- meaning the mod author's own single account can never naturally trigger
    -- it on their own faction's locked vehicles. This toggle tells the
    -- server to treat THIS player as an outsider for that one check only, so
    -- a solo tester can confirm ejection/tow-detach actually happens.
    local lockTestCard = FFCard:new(x, y, innerW, 0,
        FF.text("UI_LFS_DebugLockTestCardTitle", "TESTE DE TRAVA"))
    lockTestCard:initialise(); lockTestCard:instantiate()
    local ly = lockTestCard:contentTop()

    local lockTestMsg = FF.text("UI_LFS_DebugLockTestDesc",
        "Trata você como se não fosse da sua própria facção, só para veículos trancados -- use para testar se a expulsão/desengate de reboque funciona.")
    for _, line in ipairs(wrapText(lockTestMsg, UI.font.small, innerW - 2 * pad)) do
        cardText(lockTestCard, pad, ly, line, c.dim, UI.font.small)
        ly = ly + UI.lineH(UI.font.small)
    end
    ly = ly + 6

    local lockTestOn = FF.debugLockSelfTestActive == true
    local lockTestLabel = lockTestOn
        and FF.text("UI_LFS_DebugLockTestOn", "Ativo -- clique para desativar")
        or FF.text("UI_LFS_DebugLockTestOff", "Inativo -- clique para ativar")
    local lockTestBtnW = UI.buttonWidth(lockTestLabel, false, EH)
    local lockTestBtn = FFButton:new(pad, ly, lockTestBtnW, EH, lockTestLabel,
        self, LasciviousFactionsSystemPanel.onDebugToggleLockSelfTest, lockTestOn and "primary" or "ghost")
    lockTestBtn:initialise(); lockTestBtn:instantiate()
    lockTestCard:addChild(lockTestBtn)
    ly = ly + EH + pad

    lockTestCard:setContentHeight(ly)
    scroll:addChild(lockTestCard)
    y = y + lockTestCard:getHeight() + 10

    scroll:setScrollHeight(y)
end

function LasciviousFactionsSystemPanel:onDebugToggleLockSelfTest(button)
    -- Module-level, not self.xxx, for two reasons: FF.vehicleLockBlocksCharacter
    -- (LFS_VehicleGuard.lua) reads this directly since the preventative enter/gas/
    -- parts guards run partly or fully on THIS client and can't wait on the
    -- server's debugIgnoreOwnLock round trip the way the reactive eject tick can;
    -- and a fresh panel instance (close/reopen) must not forget the real toggle
    -- state and default the button back to "Inativo".
    FF.debugLockSelfTestActive = not (FF.debugLockSelfTestActive == true)
    send("debugToggleLockSelfTest", { enabled = FF.debugLockSelfTestActive })
    self:showSection("debug")
end

-- Locks a fresh capture onto whichever vehicle is currently nearest (see
-- FF.nearestVehicle) -- a fresh table every time, not a toggle/reset, so
-- re-clicking mid-capture restarts cleanly with no leftover totals.
function LasciviousFactionsSystemPanel:onDebugCaptureVehicle(button)
    local vehicle = FF.nearestVehicle(VEHICLE_SCAN_RADIUS)
    if not vehicle then return end
    local baseline = FF.readVehicleMaintState(vehicle)
    FF.vehicleMaintAccumulation = {
        active = true, vehicle = vehicle, vehicleId = vehicle:getId(), ticksTotal = 60, ticksRemaining = 60,
        startedAt = getTimestamp(), baseline = baseline, last = baseline,
    }
    self:showSection("debug")
end

-- Debug > Caçador: live read of the current detection state (never mutates
-- anything) plus the self-test toggle. Shows the RAW username and circle
-- centre/radius for every currently-detected outsider regardless of upgrade
-- level -- unlike the real Território map (LFS_ClaimMap.lua's
-- _drawHunterCircles, which only ever shows the name at level 10), this is
-- explicitly a debug tool for the mod author, gated the same as every other
-- Debug sub-tab.
function LasciviousFactionsSystemPanel:populateDebugHunter()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end
    FF.ensureHunterTracking(faction)

    local c = UI.color
    local x = UI.pad
    local headerY = self:addHeader(name, faction, username)

    local scroll = ISPanel:new(0, headerY, self.content:getWidth(), self.content:getHeight() - headerY)
    scroll:initialise(); scroll:instantiate()
    scroll.background = false
    scroll:setScrollChildren(true)
    scroll:addScrollBars()
    setupScrollPane(scroll)
    self.content:addChild(scroll)
    self.activeScroll = scroll

    local innerW = self.content:getWidth() - 2 * UI.pad - 16
    local y = UI.pad
    local pad = 12
    local EH = UI.rowH(UI.font.body)

    local level = FF.upgradeLevel(faction, "hunter")
    local note = Notice:new(x, y, innerW,
        FF.text("UI_LFS_DebugHunterWarning",
            "Leitura ao vivo da detecção do Caçador -- nunca altera nada, apenas mostra o que o servidor está vendo. Nível atual: %s (alcance: %s tiles).",
            tostring(level), tostring(FF.hunterMaxRange(level))),
        UI.color.warn, "ic_flame")
    note:initialise(); scroll:addChild(note)
    y = y + note:getHeight() + 10

    -- Self-test toggle. The reactive vehicle-lock guard tick has its own
    -- separate debug flag (Debug > Veículos) -- this is a DIFFERENT
    -- mechanism (LFS_Server.lua's debugIgnoreOwnHunterMembership), specific
    -- to hunter detection, so a solo tester can see themselves appear as a
    -- detected blip on their own faction's map.
    local testCard = FFCard:new(x, y, innerW, 0,
        FF.text("UI_LFS_DebugHunterTestCardTitle", "TESTE DE DETECÇÃO"))
    testCard:initialise(); testCard:instantiate()
    local ty = testCard:contentTop()

    local testMsg = FF.text("UI_LFS_DebugHunterTestDesc",
        "Trata você como se não fosse da sua própria facção, só para o Caçador -- use para se ver detectado no mapa de Território.")
    for _, line in ipairs(wrapText(testMsg, UI.font.small, innerW - 2 * pad)) do
        cardText(testCard, pad, ty, line, c.dim, UI.font.small)
        ty = ty + UI.lineH(UI.font.small)
    end
    ty = ty + 6

    local testOn = FF.debugHunterSelfTestActive == true
    local testLabel = testOn
        and FF.text("UI_LFS_DebugHunterTestOn", "Ativo -- clique para desativar")
        or FF.text("UI_LFS_DebugHunterTestOff", "Inativo -- clique para ativar")
    local testBtnW = UI.buttonWidth(testLabel, false, EH)
    local testBtn = FFButton:new(pad, ty, testBtnW, EH, testLabel,
        self, LasciviousFactionsSystemPanel.onDebugToggleHunterSelfTest, testOn and "primary" or "ghost")
    testBtn:initialise(); testBtn:instantiate()
    testCard:addChild(testBtn)

    -- Beside the toggle, not below it -- forces hunterTrackingTick's own
    -- throttle open on the next real tick instead of waiting up to
    -- HUNTER_TICK_INTERVAL (60 real seconds), so a tester who just walked
    -- out of their circle doesn't have to sit around to see the result.
    local forceLabel = FF.text("UI_LFS_DebugHunterForceScan", "Forçar atualizar agora")
    local forceBtnW = UI.buttonWidth(forceLabel, false, EH)
    local forceBtn = FFButton:new(pad + testBtnW + UI.gap, ty, forceBtnW, EH, forceLabel,
        self, LasciviousFactionsSystemPanel.onDebugForceHunterScan, "ghost")
    forceBtn:initialise(); forceBtn:instantiate()
    testCard:addChild(forceBtn)
    ty = ty + EH + pad

    testCard:setContentHeight(ty)
    scroll:addChild(testCard)
    y = y + testCard:getHeight() + 10

    -- Currently-detected list, sorted by username for a stable read across
    -- frames (faction.hunter.detected is a plain dict, pairs() has no
    -- defined order).
    local detected = faction.hunter.detected or {}
    local ids = {}
    for uname in pairs(detected) do ids[#ids + 1] = uname end
    table.sort(ids)

    local listCard = FFCard:new(x, y, innerW, 0,
        FF.text("UI_LFS_DebugHunterDetectedCardTitle", "DETECTADOS AGORA"))
    listCard:initialise(); listCard:instantiate()
    local ly = listCard:contentTop()
    if #ids == 0 then
        cardText(listCard, pad, ly, FF.text("UI_LFS_DebugHunterNone", "Nenhum jogador detectado no momento."),
            c.dim, UI.font.small)
        ly = ly + UI.lineH(UI.font.small)
    else
        local debugLive = faction.hunter.debugLive or {}
        for _, uname in ipairs(ids) do
            local entry = detected[uname]
            local line = FF.text("UI_LFS_DebugHunterEntry",
                "%s -- centro (%s, %s), raio %s tiles%s",
                uname, tostring(entry.cx), tostring(entry.cy), tostring(math.floor(entry.radius + 0.5)),
                entry.name and (" -- " .. FF.text("UI_LFS_DebugHunterNameRevealed", "nome revelado")) or "")
            cardText(listCard, pad, ly, line, entry.name and c.accent or c.text2, UI.font.small)
            ly = ly + UI.lineH(UI.font.small)

            -- Live telemetry (real position/live distance), ONLY present while
            -- that username is under the self-test flag -- server only ever
            -- populates faction.hunter.debugLive for debugIgnoreOwnHunterMembership
            -- usernames, refreshed every hunterTrackingTick poll regardless of
            -- whether the circle itself needed regenerating.
            local live = debugLive[uname]
            if live then
                local liveLine = FF.text("UI_LFS_DebugHunterLiveEntry",
                    "   ao vivo: posição real (%s, %s), distância %s tiles",
                    tostring(math.floor(live.px)), tostring(math.floor(live.py)),
                    tostring(math.floor(live.distance + 0.5)))
                cardText(listCard, pad, ly, liveLine, c.dim, UI.font.small)
                ly = ly + UI.lineH(UI.font.small)
            end
        end
    end
    ly = ly + 6
    listCard:setContentHeight(ly)
    scroll:addChild(listCard)
    y = y + listCard:getHeight() + 10

    scroll:setScrollHeight(y)
end

function LasciviousFactionsSystemPanel:onDebugToggleHunterSelfTest(button)
    -- Module-level, not self.xxx: a fresh panel instance (close/reopen) must not
    -- forget the real toggle state and default the button back to "Inativo" --
    -- see FF.debugLockSelfTestActive above for the same fix on the vehicle-lock
    -- self-test, applied here after the user flagged this exact confusion.
    FF.debugHunterSelfTestActive = not (FF.debugHunterSelfTestActive == true)
    send("debugToggleHunterSelfTest", { enabled = FF.debugHunterSelfTestActive })
    self:showSection("debug")
end

function LasciviousFactionsSystemPanel:onDebugForceHunterScan(button)
    send("debugForceHunterScan", {})
    -- The scan itself happens server-side on the next real tick, not
    -- synchronously with this click -- no local state to flip here, this
    -- just re-renders so the section is ready to pick up the result via the
    -- normal liveRefreshFingerprint poll once it lands.
    self:showSection("debug")
end

-- Personal preference, per-player: draw the Caçador's detection circles (and
-- its max-range boundary) on the REAL world map/minimap (LFS_MapOverlay.lua's
-- drawHunterCircles/drawHunterRange), not just the embedded Território map.
-- Persisted on the CHARACTER's own modData (survives relog, never touches the
-- server -- nothing here needs to be shared with anyone else, each member
-- decides this purely for themselves). A plain button, not a toggle switch --
-- short enough to sit beside Draw/Erase and read its own state from its label
-- + colour, same convention as every debug self-test button above.
function LasciviousFactionsSystemPanel:onHunterAlwaysShowToggle(button)
    local player = getPlayer()
    if not player then return end
    local md = player:getModData()
    md.LFS_hunterShowOnWorldMap = (md.LFS_hunterShowOnWorldMap ~= true) or nil
    self:showSection("claims")
end

-- Faction tribute: treasury balance, current rate (read-only here -- set from the
-- Settings tab, owner-only), Deposit+Withdraw (manageTribute permission or owner)
-- or a single Donate (everyone else), and the last 100 deposits/withdrawals
-- (server-capped; passive per-tick tax collection never appears here).
local function formatCreditsFixed(value)
    local LS = _G.LasciviousShop
    if LS and type(LS.formatCreditsFixed) == "function" then
        local ok, formatted = pcall(LS.formatCreditsFixed, value)
        if ok and formatted then return formatted end
    end
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then value = 0 end
    return (string.gsub(string.format("%.2f", value), "%.", ","))
end

function LasciviousFactionsSystemPanel:populateTribute()
    self.tributeDepositBtn, self.tributeWithdrawBtn, self.tributeDonateBtn = nil, nil, nil

    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end
    FF.ensureTribute(faction)
    local tribute = faction.tribute
    local c = UI.color

    local x = UI.pad
    local innerW = self.content:getWidth() - 2 * UI.pad
    local y = self:addHeader(name, faction, username)
    local canManage = FF.roleCan(faction, username, "manageTribute")
    local pad = 12
    local EH = UI.rowH(UI.font.body)

    local card = FFCard:new(x, y, innerW, 0, FF.text("UI_LFS_TributeCardTitle", "TESOURO DA FACÇÃO"))
    card:initialise(); card:instantiate()
    local cy = card:contentTop()

    local balLbl = ISLabel:new(pad, cy, UI.fh(UI.font.small), FF.text("UI_LFS_TributeBalanceLabel", "Saldo"),
        c.dim.r, c.dim.g, c.dim.b, 1.0, UI.font.small, true)
    balLbl:initialise(); card:addChild(balLbl)
    cy = cy + UI.lineH(UI.font.small)
    local balValue = ISLabel:new(pad, cy, UI.fh(UI.font.title),
        formatCreditsFixed(tribute.balance) .. " cr", c.accentText.r, c.accentText.g,
        c.accentText.b, 1.0, UI.font.title, true)
    balValue:initialise(); card:addChild(balValue)
    cy = cy + UI.lineH(UI.font.title) + 6

    local rateLbl = ISLabel:new(pad, cy, UI.fh(UI.font.body),
        FF.text("UI_LFS_TributeRateLabel", "Alíquota atual: %s%%", tostring(math.floor(tribute.ratePercent or 0))),
        c.text2.r, c.text2.g, c.text2.b, 1.0, UI.font.body, true)
    rateLbl:initialise(); card:addChild(rateLbl)
    cy = cy + UI.lineH(UI.font.body) + 10

    if canManage then
        local bw = (innerW - 2 * pad - 8) / 2
        local deposit = FFButton:new(pad, cy, bw, EH, FF.text("UI_LFS_TributeDepositAction", "Depositar"),
            self, LasciviousFactionsSystemPanel.onTributeDeposit, "primary")
        deposit:initialise(); deposit:instantiate(); card:addChild(deposit)
        self.tributeDepositBtn = deposit
        local withdraw = FFButton:new(pad + bw + 8, cy, bw, EH, FF.text("UI_LFS_TributeWithdrawAction", "Sacar"),
            self, LasciviousFactionsSystemPanel.onTributeWithdraw, "ghost")
        withdraw:initialise(); withdraw:instantiate(); card:addChild(withdraw)
        self.tributeWithdrawBtn = withdraw
    else
        local donate = FFButton:new(pad, cy, innerW - 2 * pad, EH, FF.text("UI_LFS_TributeDonateAction", "Doar"),
            self, LasciviousFactionsSystemPanel.onTributeDonate, "primary")
        donate:initialise(); donate:instantiate(); card:addChild(donate)
        self.tributeDonateBtn = donate
    end
    cy = cy + EH + pad

    -- Tesouraria upgrade hint: small, discreet, right at the very end of
    -- this card -- explicit user spec ("bem no finalzinho do card que fala
    -- o saldo, dizer embaixo, bem discreto"). Only shows once the faction
    -- actually has a level in this upgrade; level 0 (or no active claim,
    -- same rule every other upgrade effect follows) leaves the card exactly
    -- as it was before this feature existed.
    local treasuryLevel = FF.upgradeLevel(faction, "treasury")
    if treasuryLevel > 0 and FF.upgradesActive(faction) then
        local ratePercent = treasuryLevel * 0.1
        local rateText = string.gsub(string.format("%.1f", ratePercent), "%.", ",")
        local yieldLbl = ISLabel:new(pad, cy, UI.fh(UI.font.small),
            FF.text("UI_LFS_TributeYieldHint", "Rendimento de %s%% ao dia", rateText),
            c.dim.r, c.dim.g, c.dim.b, 1.0, UI.font.small, true)
        yieldLbl:initialise(); card:addChild(yieldLbl)
        cy = cy + UI.lineH(UI.font.small) + 4
    end

    card:setContentHeight(cy)
    self.content:addChild(card)
    y = y + card:getHeight() + 10

    -- History: last 100 deposits/withdrawals, newest first, server-capped already
    -- (see LFS_Server.lua's appendTributeHistory) -- the client just renders it.
    -- PLUS, pinned permanently at the very top (not a real entry in
    -- tribute.history, doesn't age out, doesn't scroll away as real entries
    -- accumulate): the Tesouraria upgrade's last daily interest payout, if
    -- one has ever happened -- explicit user spec ("um lançamento
    -- permanente, que fica sempre no topo... só mostra o que rendeu das
    -- últimas 24 horas"). tribute.lastInterestAmount only ever gets set by
    -- LFS_Server.lua's treasuryInterestTick, and upgrade levels never
    -- decrease once bought, so its mere presence is enough to show this --
    -- no separate "does the faction still have the upgrade" re-check needed.
    local histCard = FFCard:new(x, y, innerW, math.max(80, self.content:getHeight() - y - UI.pad),
        FF.text("UI_LFS_TributeHistoryCardTitle", "HISTÓRICO"))
    histCard:initialise(); histCard:instantiate()
    local topY = histCard:contentTop()
    local history = tribute.history or {}
    local lastInterestAmount = tonumber(tribute.lastInterestAmount)
    if #history == 0 and lastInterestAmount == nil then
        local empty = ISLabel:new(pad, topY, UI.fh(UI.font.body),
            FF.text("UI_LFS_TributeHistoryEmpty", "Nenhuma movimentação ainda."), c.dim.r, c.dim.g, c.dim.b,
            1.0, UI.font.body, true)
        empty:initialise(); histCard:addChild(empty)
    else
        local scroll = ISPanel:new(pad, topY, histCard:getWidth() - 2 * pad, histCard:getHeight() - topY - pad)
        scroll:initialise(); scroll:instantiate()
        scroll.background = false
        scroll:setScrollChildren(true)
        scroll:addScrollBars()
        setupScrollPane(scroll)
        histCard:addChild(scroll)
        local rowH = UI.lineH(UI.font.body)
        local ry = 0
        if lastInterestAmount ~= nil then
            local interestText = FF.text("UI_LFS_TributeInterestHistoryLine",
                "Rendimento das últimas 24 horas: %s cr", formatCreditsFixed(lastInterestAmount))
            local interestLbl = ISLabel:new(0, ry, UI.fh(UI.font.body), interestText,
                c.accent.r, c.accent.g, c.accent.b, 1.0, UI.font.body, true)
            interestLbl:initialise(); scroll:addChild(interestLbl)
            ry = ry + rowH
        end
        for i = #history, 1, -1 do
            local entry = history[i]
            local isDeposit = entry.kind == "deposit"
            local amountText = (isDeposit and "+" or "-") .. formatCreditsFixed(entry.amount) .. " cr"
            local verb = isDeposit and FF.text("UI_LFS_TributeHistoryDeposited", "%s depositou", tostring(entry.actor))
                or FF.text("UI_LFS_TributeHistoryWithdrew", "%s sacou", tostring(entry.actor))
            local rowLbl = ISLabel:new(0, ry, UI.fh(UI.font.body), verb .. " " .. amountText,
                (isDeposit and c.good or c.bad).r, (isDeposit and c.good or c.bad).g,
                (isDeposit and c.good or c.bad).b, 1.0, UI.font.body, true)
            rowLbl:initialise(); scroll:addChild(rowLbl)
            ry = ry + rowH
        end
        scroll:setScrollHeight(ry)
    end
    self.content:addChild(histCard)
end

function LasciviousFactionsSystemPanel:onTributeDeposit()
    local w = TributeAmountDialog:new("deposit")
    w:initialise(); w:instantiate(); w:addToUIManager(); w:bringToTop()
end

function LasciviousFactionsSystemPanel:onTributeWithdraw()
    local w = TributeAmountDialog:new("withdraw")
    w:initialise(); w:instantiate(); w:addToUIManager(); w:bringToTop()
end

function LasciviousFactionsSystemPanel:onTributeDonate()
    local w = TributeAmountDialog:new("donate")
    w:initialise(); w:instantiate(); w:addToUIManager(); w:bringToTop()
end

-- Per-frame refresh of the Claims controls while that tab is open (button enable
-- states and the Draw toggle's look track the map's live pending-claim state).
function LasciviousFactionsSystemPanel:refreshClaimControls()
    local map = self.claimMap
    if not map then return end

    -- Both of these are expensive and both were being called several times per frame
    -- from the blocks below -- proposedInfo twice, hasChanges three times. proposedInfo
    -- runs a PhunZones spatial query per pending rect (and a nested walk over every
    -- point of every zone it gets back); hasChanges builds two sorted, concatenated
    -- signature strings to compare. Compute each once and thread the results through.
    local total, maxTiles, valid, reason
    if map.proposedInfo then total, maxTiles, valid, reason = map:proposedInfo() end
    local changed = map:hasChanges()

    -- The capacity bar tracks the pending selection while it differs from the saved
    -- claim: green when the proposal is legal, red when it isn't (over the tile cap,
    -- overlapping someone else's ground, too many separate areas).
    if self.claimCapBar and map.proposedInfo and not map.failed then
        local s = FF.text("UI_LFS_DynamicTiles", "%d / %d tiles",
            math.floor(total + 0.5), math.floor(maxTiles + 0.5))
        -- The "N / max areas" count signals that a claim may be several separate boxes
        -- (one per building), which is the tool's least discoverable capability.
        if map.areaCount then
            local areas, maxAreas = map:areaCount()
            s = s .. "   " .. FF.text("UI_LFS_ClaimAreaUsage", "%d / %d areas", areas, maxAreas)
        end
        -- Say WHY Submit is disabled. Reasons like "too many public areas" come from
        -- an edit in the area list rather than a drag, so the drag preview's own
        -- explanation never appears for them.
        if changed and not valid and FFClaimMap.reasonText then
            local why = FFClaimMap.reasonText(reason)
            if why then s = s .. "   -   " .. why end
        end
        self.claimCapBar.label = s
        self.claimCapBar.fraction = (maxTiles > 0) and (total / maxTiles) or 0
        self.claimCapBar.color = changed and (valid and UI.color.good or UI.color.bad) or nil
    end

    if self.claimDrawBtn then
        -- Shop mode IS a draw mode, so isDrawMode() is true for both. Without excluding
        -- it here, arming the shop button lights up "Drawing..." as well and the player
        -- sees two active modes at once.
        local drawing = map:isDrawMode() and not (map.isShopMode and map:isShopMode())
        self.claimDrawBtn.title = FF.tr(drawing and "Drawing..." or "Draw claim")
        self.claimDrawBtn.variant = drawing and "primary" or "ghost"
    end
    if self.claimEraseBtn then
        local erasing = map:isEraseMode()
        self.claimEraseBtn.title = FF.tr(erasing and "Erasing..." or "Erase")
        self.claimEraseBtn.variant = erasing and "primary" or "ghost"
    end
    if self.claimShopBtn and map.isShopMode then
        -- Armed state says what to do next; the button is already teal-tinted, so the
        -- label carries the instruction rather than a colour change nobody would read.
        self.claimShopBtn.title = FF.tr(map:isShopMode() and "Drag out the area..." or "Make a Public Area")
        -- Recomputed every frame rather than only at build time: the public-area budget
        -- is spent by drawing and freed by deleting a row in the area list, both of
        -- which happen without rebuilding this tab.
        local used, maxPublic = map:publicAreaCount()
        self.claimShopBtn:setEnable(maxPublic > 0 and used < maxPublic)
    end
    if self.claimSubmitBtn then
        self.claimSubmitBtn:setEnable((changed and valid) and true or false)
    end
    if self.claimClearBtn then
        self.claimClearBtn:setEnable(changed)
    end
end

function LasciviousFactionsSystemPanel:onClaimDrawToggle(button)
    if self.claimMap then self.claimMap:setDrawMode(not self.claimMap:isDrawMode()) end
end

function LasciviousFactionsSystemPanel:onClaimEraseToggle(button)
    if self.claimMap then self.claimMap:setEraseMode(not self.claimMap:isEraseMode()) end
end

function LasciviousFactionsSystemPanel:onShopClaimToggle(button)
    if self.claimMap then self.claimMap:setShopMode(not self.claimMap:isShopMode()) end
end

function LasciviousFactionsSystemPanel:onClaimSubmit(button)
    if self.claimMap then self.claimMap:submit() end
end

function LasciviousFactionsSystemPanel:onClaimClear(button)
    if self.claimMap then self.claimMap:refresh(true) end   -- force-discard pending edits
end

function LasciviousFactionsSystemPanel:onUnclaimClick(button)
    local modal = ISModalDialog:new(0, 0, 320, 130,
        FF.tr("Remove your faction's claim entirely?"), true, self,
        LasciviousFactionsSystemPanel.onUnclaimConfirm)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end

function LasciviousFactionsSystemPanel:onUnclaimConfirm(button)
    if button.internal == "YES" then send("unclaim") end
end

function LasciviousFactionsSystemPanel:onSetRespawnClick(button)
    send("setRespawn")
end

-- ---------------------------------------------------------------------------
-- Raid
-- ---------------------------------------------------------------------------
function LasciviousFactionsSystemPanel:populateRaid()
    local username = getPlayer():getUsername()
    local name, faction = FF.getFactionOfPlayer(username)
    if not faction then
        self:addLabel(UI.pad, (self.sectionTop or 0) + 14, "You're not in a faction.", UI.color.text, UI.font.title)
        return
    end

    local x = UI.pad
    local innerW = self.content:getWidth() - 2 * UI.pad
    local y = self:addHeader(name, faction, username)

    if faction.raid then
        self:drawRaidProgress(name, faction.raid.attacker, x, y, innerW, false)
        return
    end

    local attackingDefender = nil
    for otherName, other in pairs(FF.getData().factions or {}) do
        if other.raid and other.raid.attacker == name then attackingDefender = otherName break end
    end
    if attackingDefender then
        self:drawRaidProgress(attackingDefender, name, x, y, innerW, true)
        return
    end

    local note = Notice:new(x, y, innerW, "No active raid.", UI.color.dim, nil)
    note:initialise(); self.content:addChild(note)
    y = y + note:getHeight() + 12

    self:addLabel(x, y, "Raid another faction's claim", UI.color.dim, UI.font.small)
    y = y + UI.lineH(UI.font.small) + 4

    local raidTargets = {}
    for otherName, other in pairs(FF.getData().factions or {}) do
        if otherName ~= name and other.claims and #other.claims > 0 then
            table.insert(raidTargets, otherName)
        end
    end
    table.sort(raidTargets)

    if #raidTargets == 0 then
        local note = Notice:new(x, y, innerW, "No factions have a claim to raid.", UI.color.dim, nil)
        note:initialise(); self.content:addChild(note)
        return
    end

    self.raidList = ISScrollingListBox:new(x, y, innerW, self.content:getHeight() - y - 12)
    self.raidList.backgroundColor = UI.color.panel
    self.raidList:initialise()
    self.raidList:instantiate()
    self.raidList.itemheight = UI.rowH(UI.font.body)   -- one line of text per row
    self.raidList.font = UI.font.body
    self.raidList.drawBorder = true
    self.raidList.borderColor = UI.color.border
    self.raidList.doDrawItem = LasciviousFactionsSystemPanel.drawSimpleRow
    self.raidList.target = self
    self.raidList.onmousedown = LasciviousFactionsSystemPanel.onRaidTargetClicked
    for _, otherName in ipairs(raidTargets) do
        self.raidList:addItem(otherName, otherName)
    end
    self.content:addChild(self.raidList)
end

function LasciviousFactionsSystemPanel:drawRaidProgress(defenderName, attackerName, x, y, innerW, iAmAttacker)
    local strip = Notice:new(x, y, innerW,
        FF.text("UI_LFS_DynamicAttacking", "%s attacking %s", attackerName, defenderName),
        UI.color.bad, "ic_flame")
    strip:initialise(); self.content:addChild(strip)
    y = y + strip:getHeight() + 10

    local progress = LasciviousFactionsSystemPanel.raidProgress[defenderName]
    local held = progress and progress.held or 0
    local need = progress and progress.need or 1
    local attackers = progress and progress.attackers or 0
    local defenders = progress and progress.defenders or 0

    local card = FFCard:new(x, y, innerW, 0, "SIEGE")
    card:initialise(); card:instantiate(); self.content:addChild(card)
    local sgy = card:contentTop()
    sgy = self:addStatRow(card, 12, sgy, innerW - 24, "Attackers vs defenders",
        FF.text("UI_LFS_RaidVersus", "%d vs %d", attackers, defenders),
        attackers > defenders and UI.color.bad or UI.color.accent)
    sgy = sgy + 4
    local raidBar = FFBar:new(12, sgy, innerW - 24, 14)
    raidBar:initialise()
    raidBar.fraction = held / math.max(1, need)
    raidBar.color = UI.color.bad
    card:addChild(raidBar)
    y = y + card:setContentHeight(sgy + 14) + 12

    -- Give-up + admin controls under the siege card.
    local username = getPlayer():getUsername()
    local _, myFaction = FF.getFactionOfPlayer(username)
    local canAbandon = iAmAttacker and myFaction and FF.roleCan(myFaction, username, "startRaid")
    local bx = x
    local RBH = UI.rowH(UI.font.body)
    if canAbandon then
        local abW = UI.buttonWidth("Abandon raid", false, RBH)
        local btn = FFButton:new(bx, y, abW, RBH, "Abandon raid", self, LasciviousFactionsSystemPanel.onAbandonRaidClick, "danger")
        btn:initialise(); btn:instantiate(); self.content:addChild(btn)
        bx = bx + abW + 10
    end
    -- Admins can force-end any raid they can see; defenders keep the claim either way.
    if FF.isLocalAdmin and FF.isLocalAdmin() then
        local ebtn = FFButton:new(bx, y, UI.buttonWidth("End raid (admin)", false, RBH), RBH, "End raid (admin)",
            self, LasciviousFactionsSystemPanel.onAdminEndRaidClick, "ghost")
        ebtn.raidDefender = defenderName
        ebtn:initialise(); ebtn:instantiate(); self.content:addChild(ebtn)
    end
end

function LasciviousFactionsSystemPanel:onAbandonRaidClick()
    local modal = ISModalDialog:new(0, 0, 360, 130,
        FF.tr("Call off your raid? The defender keeps their claim."),
        true, self, LasciviousFactionsSystemPanel.onAbandonRaidConfirm)
    modal:initialise(); modal:addToUIManager(); modal:setAlwaysOnTop(true); modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end
function LasciviousFactionsSystemPanel:onAbandonRaidConfirm(button)
    if button.internal == "YES" then send("abandonRaid", {}) end
end
-- Confirmed, like the "Abandon raid" button three rows above it. It was the odd one
-- out: the player-facing button that ends the player's OWN raid asks first, while the
-- admin button that ends somebody else's fired on a single click.
function LasciviousFactionsSystemPanel:onAdminEndRaidClick(button)
    local def = button and button.raidDefender
    if not def then return end
    -- ISModalDialog param1 rides through to onclick's 3rd arg, carrying the defender.
    local modal = ISModalDialog:new(0, 0, 380, 140,
        FF.text("UI_LFS_EndRaidConfirm",
            "End the raid on %s?\n\nThe defenders keep their claim.", tostring(def)),
        true, self, LasciviousFactionsSystemPanel.onAdminEndRaidConfirm, nil, def)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end
function LasciviousFactionsSystemPanel:onAdminEndRaidConfirm(button, def)
    if button.internal == "YES" then send("adminEndRaid", { defender = def }) end
end

function LasciviousFactionsSystemPanel:onRaidTargetClicked(targetName)
    local modal = ISModalDialog:new(0, 0, 340, 140,
        FF.text("UI_LFS_StartRaidConfirm", "Start a raid on %s?", targetName),
        true, self, LasciviousFactionsSystemPanel.onRaidConfirm, nil, targetName)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
    modal:setX((getCore():getScreenWidth() - modal.width) / 2)
    modal:setY((getCore():getScreenHeight() - modal.height) / 2)
end

function LasciviousFactionsSystemPanel:onRaidConfirm(button, targetName)
    if button.internal == "YES" then
        send("startRaid", { target = targetName })
    end
end

-- ---------------------------------------------------------------------------
-- Window lifecycle
-- ---------------------------------------------------------------------------
function LasciviousFactionsSystemPanel:close()
    -- Remember size/position/collapsed so the next open restores this layout.
    pcall(function() self:savePanelState() end)
    -- Clear the static handle FIRST, so even if the teardown below throws (e.g. on a
    -- half-destroyed window) we never leave a stale instance that blocks reopening.
    if LasciviousFactionsSystemPanel.instance == self then
        LasciviousFactionsSystemPanel.instance = nil
    end
    -- UI.dimAlpha is shared across every FF* widget (see UI.installDimming),
    -- not per-instance -- only updateDangerAlpha() writes it, and that only
    -- runs while this panel's own prerender is ticking. Without this reset a
    -- panel closed mid-fade (e.g. via checkAttackedClose while still dimmed)
    -- would leave it stuck below 1.0 for anything else built from those
    -- classes (the /ff admin uitest harness, any dialog reused later) until
    -- the panel happened to be reopened and glide it back up.
    UI.dimAlpha = 1.0
    pcall(function()
        self:setVisible(false)
        self:removeFromUIManager()
    end)
end

-- Escape closes the panel. isKeyConsumed(ESCAPE)=true stops the same press from also
-- opening the game's pause menu (the vanilla ISBaseEntityWindow pattern).
-- True while the vanilla world map is open on top of us (opened the normal way,
-- independent of this panel), and this window consumes Escape -- which would
-- otherwise leave the map unclosable while the panel is open behind it. Both
-- Escape handlers stand down for as long as the map is up.
local function worldMapOpen()
    local inst = _G.ISWorldMap_instance
    if not inst then return false end
    local ok, visible = pcall(function() return inst:isReallyVisible() end)
    return ok and visible or false
end

function LasciviousFactionsSystemPanel:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE and not worldMapOpen()
end

function LasciviousFactionsSystemPanel:onKeyRelease(key)
    if key ~= Keyboard.KEY_ESCAPE then return end
    if worldMapOpen() then return end   -- that Escape belongs to the map
    -- Don't close out from under an active text field (roles/settings tabs); let
    -- Escape blur it first.
    local editing = anyEntryFocused(self.roleNameEntry, self.roleRenameEntry,
        self.settingsTagEntry, self.settingsDescEntry)
    if not editing then self:close() end
end

function LasciviousFactionsSystemPanel:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.anim = 0
    o.baseY = y
    o.dragging = false
    o.pendingClose = false
    o.pendingMinimize = false
    o._resizing = false
    o.collapsed = false
    o.restoreHeight = height
    o.navRects = {}
    o.navHoverT = {}
    o.indicatorY = -1
    o.moveWithMouse = false
    o.minimumWidth = MIN_WINDOW_WIDTH
    o.minimumHeight = MIN_WINDOW_HEIGHT
    o:setWantKeyEvents(true)   -- required for onKeyRelease/isKeyConsumed to fire
    return o
end

-- First-open size, scaled down to fit the player's actual screen resolution
-- (never scaled up past the WINDOW_WIDTH/HEIGHT design size -- min(1, ...)
-- caps it). Same technique as LasciviousShop_Window.lua's own
-- initialGeometry, adapted to also respect MIN_WINDOW_WIDTH/HEIGHT (the
-- floor the resize/restore path already enforces so the nav list can never
-- be dragged small enough to clip a tab -- a fresh first-ever open should
-- honour the exact same invariant). On any screen roomy enough for the
-- 800x600 design (the overwhelming majority), scale stays at 1 and this is
-- a no-op; it only matters on a genuinely small screen/window.
local SCREEN_EDGE = 12
local function initialGeometry(screenW, screenH)
    local availableW = math.max(1, screenW - SCREEN_EDGE * 2)
    local availableH = math.max(1, screenH - SCREEN_EDGE * 2)
    local scale = math.min(1, availableW / WINDOW_WIDTH, availableH / WINDOW_HEIGHT)
    local width = math.max(MIN_WINDOW_WIDTH, math.floor(WINDOW_WIDTH * scale))
    local height = math.max(MIN_WINDOW_HEIGHT, math.floor(WINDOW_HEIGHT * scale))
    return width, height
end

function LasciviousFactionsSystemPanel.toggle()
    local inst = LasciviousFactionsSystemPanel.instance
    if inst then
        -- Only treat this click as a "close" when the window is genuinely on screen.
        -- `instance` can be a STALE reference: on an MP relog/reconnect the UI is torn
        -- down without our close() running, so the handle lingers. We guard every native
        -- call and treat a missing/removed java object as "not visible", so a dead handle
        -- can never swallow the click (calling close() on an already-gone window, so the
        -- button looks dead and needs a second press) -- instead we fall through and open
        -- a fresh one.
        local ok, visible = pcall(function()
            return inst.javaObject ~= nil and not inst.removed and inst:isReallyVisible()
        end)
        if ok and visible then
            if inst.collapsed then
                -- Minimized: expand and surface it rather than closing, so the on-screen
                -- button always brings up a usable panel instead of toggling a title bar
                -- (a player who once minimized would otherwise never see the full UI again).
                pcall(function() inst:toggleCollapse() end)
                pcall(function() inst:bringToTop() end)
            else
                inst:close()
            end
            return
        end
        -- Stale / not really visible: force it out and open fresh below.
        pcall(function() inst:setVisible(false) end)
        pcall(function() inst:removeFromUIManager() end)
        LasciviousFactionsSystemPanel.instance = nil
    end
    local screenW, screenH = getCore():getScreenWidth(), getCore():getScreenHeight()
    local width, height = initialGeometry(screenW, screenH)
    local x = (screenW - width) / 2
    local y = (screenH - height) / 2

    -- Restore the per-character size/position, clamped so a layout saved on a
    -- different (bigger) monitor can't open oversized or off-screen. The window
    -- ALWAYS opens expanded -- restoring a minimized state would make the button
    -- appear to open only a title bar (and need a second click to be usable).
    local p = getPlayer()
    local md = p and p:getModData()
    local saved = md and md.FF_panelState
    if type(saved) == "table" then
        width  = math.max(MIN_WINDOW_WIDTH,  math.min(tonumber(saved.w) or width,  screenW))
        height = math.max(MIN_WINDOW_HEIGHT, math.min(tonumber(saved.h) or height, screenH))
        x = tonumber(saved.x) or x
        y = tonumber(saved.y) or y
        x = math.max(0, math.min(x, screenW - width))
        y = math.max(0, math.min(y, screenH - height))
    end

    local ui = LasciviousFactionsSystemPanel:new(x, y, width, height)
    -- Track the handle BEFORE construction: if a section builder ever errors mid-open,
    -- the next click discards this half-built window and retries cleanly, rather than
    -- leaving instance nil with a dead window so the button perpetually "does nothing".
    LasciviousFactionsSystemPanel.instance = ui
    ui:initialise()
    ui:instantiate()
    ui:addToUIManager()
    ui:setVisible(true)
    -- Baseline for checkAttackedClose(): whatever getAttackedBy() already
    -- reads as RIGHT NOW, not nil -- otherwise reopening the panel moments
    -- after a fight (before the engine clears/replaces that field) would
    -- instantly slam it shut again. Only a hit that happens AFTER this
    -- point counts as new.
    ui._lastAttacker = nil
    pcall(function()
        local player = getPlayer()
        if player then ui._lastAttacker = player:getAttackedBy() end
    end)
    return ui
end

-- Open the panel on Claims with shop mode already armed, so "/ff shop" (and anything
-- else pointing a player at opening a public area) lands them one drag away from it
-- instead of on a tab they then have to interpret.
function LasciviousFactionsSystemPanel.openShopClaim()
    local inst = LasciviousFactionsSystemPanel.instance
    local ok, visible = pcall(function()
        return inst ~= nil and inst.javaObject ~= nil and not inst.removed and inst:isReallyVisible()
    end)
    if not (ok and visible) then
        inst = LasciviousFactionsSystemPanel.toggle()
    else
        pcall(function() inst:bringToTop() end)
    end
    if not inst then return end
    pcall(function()
        inst:showSection("claims")
        -- showSection builds the tab, which is what creates claimMap; arming before
        -- that would be dropped on the floor.
        if inst.claimMap and inst.claimMap.setShopMode then
            inst.claimMap:setShopMode(true)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Rebindable hotkey (Options > Mods > Lascivious Factions System) + raw key listener
-- ---------------------------------------------------------------------------
local modOptions = PZAPI.ModOptions:create("LasciviousFactionsSystem", "Lascivious Factions System")
modOptions:addKeyBind("LasciviousFactionsSystem.togglePanel",
    FF.text("UI_LFS_OptionTogglePanel", "Toggle faction panel"), Keyboard.KEY_J)

-- Per-client override for where the faction button lives. "Server default" (the default)
-- defers to the server-wide HudIconPosition sandbox var, so existing players and admin
-- config are unchanged until someone opts in. Order fixes the getValue() indices below.
local hudPosOption = modOptions:addComboBox("LasciviousFactionsSystem.hudIconPosition",
    FF.text("UI_LFS_OptionButtonLocation", "Faction button location"))
hudPosOption:addItem(FF.text("UI_LFS_OptionServerDefault", "Server default"), true)
hudPosOption:addItem(FF.text("UI_LFS_OptionHidden", "Hidden"), false)
hudPosOption:addItem(FF.text("UI_LFS_OptionLeftSidebar", "Left sidebar"), false)
hudPosOption:addItem(FF.text("UI_LFS_OptionTopRight", "Top-right corner"), false)

-- Resolve the effective button location for THIS client: 0 hidden / 1 left sidebar /
-- 2 top-right corner. Reads the combo above; "Server default" (index 1) or any failure
-- falls back to the sandbox var. pcall-guarded so a ModOptions API change degrades to the
-- server-wide behaviour rather than erroring.
function FF.hudIconPosition()
    local sandbox = FF.getOptions().hudIconPosition or 1
    local ok, sel = pcall(function()
        local opt = modOptions:getOption("LasciviousFactionsSystem.hudIconPosition")
        return opt and opt:getValue()
    end)
    local resolved
    if not ok or not sel or sel == 1 then
        resolved = sandbox -- Server default / unavailable
    else
        resolved = sel - 2 -- 2->0 Hidden, 3->1 Left sidebar, 4->2 Top-right corner
    end
    -- Server-wide master switch for the LEFT sidebar entry. The native Client >
    -- Faction route and the J hotkey remain available; top-right is a distinct mode.
    if resolved == 1 and not FF.getOptions().showFactionSidebarButton then return 0 end
    return resolved
end

-- Overhead faction name tags: which factions' tags this client shows above heads.
-- Default "All factions" so you can identify anyone's allegiance on sight; players who
-- prefer the old behaviour or none can dial it back here.
local nameplateOption = modOptions:addComboBox("LasciviousFactionsSystem.nameplateMode",
    FF.text("UI_LFS_OptionNameTags", "Overhead faction name tags"))
nameplateOption:addItem(FF.text("UI_LFS_OptionAllFactions", "All factions"), true)
nameplateOption:addItem(FF.text("UI_LFS_OptionMineAllies", "My faction and allies"), false)
nameplateOption:addItem(FF.text("UI_LFS_OptionOff", "Off"), false)

-- In-world claim borders: whether/when the ground-edge highlight of nearby claims shows.
local borderOption = modOptions:addComboBox("LasciviousFactionsSystem.claimBorderMode",
    FF.text("UI_LFS_OptionClaimBorders", "Claim borders in world"))
borderOption:addItem(FF.text("UI_LFS_OptionOn", "On"), true)
borderOption:addItem(FF.text("UI_LFS_OptionNear", "Only when near"), false)
borderOption:addItem(FF.text("UI_LFS_OptionOff", "Off"), false)

-- Per-client toggle for the seasonal HUD banner (the top-centre ticker showing season
-- rank + live war score). The server can still hard-disable it for everyone via the
-- ShowHudTicker sandbox var; this only lets a client hide it for themselves when the
-- server has it on. Default on, so nothing changes until a player opts out.
local hudTickerOption = modOptions:addTickBox("LasciviousFactionsSystem.showHudTicker",
    FF.text("UI_LFS_OptionSeasonBanner", "Show seasonal HUD banner"), true)

-- Admin-only moderation view: draw EVERY faction's claims on the world map and minimap,
-- ignoring the ally/pact map-sharing rules. Off by default, and the accessor re-checks
-- the local access level on every call -- ticking this as a non-admin does nothing, and
-- an admin who is demoted mid-session loses it without needing to untick anything.
-- Purely a local draw filter: it sends nothing, changes no state, and is invisible to
-- other players. Admins already bypass claim build/craft permissions everywhere
-- (LFS_Permissions.lua), so this sits at the same trust level.
local adminClaimsOption = modOptions:addTickBox("LasciviousFactionsSystem.adminSeeAllClaims",
    FF.text("UI_LFS_OptionAdminClaims", "Admin: show ALL faction claims on the map"), false)

-- Effective overhead-nameplate mode for THIS client: 0 off / 1 mine+allies / 2 all.
-- The client combo controls scope, but the server can hard-disable the feature entirely
-- via the ShowNameplates sandbox var (0). pcall-guarded; defaults to "all".
function FF.nameplateMode()
    if (FF.getOptions().showNameplates or 0) <= 0 then return 0 end   -- server disabled
    local ok, sel = pcall(function()
        local opt = modOptions:getOption("LasciviousFactionsSystem.nameplateMode")
        return opt and opt:getValue()
    end)
    if not ok or not sel then return 2 end
    if sel == 3 then return 0 elseif sel == 2 then return 1 else return 2 end  -- 1 All / 2 Mine+allies / 3 Off
end

-- Effective seasonal-HUD-banner visibility for THIS client: the server master switch
-- (ShowHudTicker) AND the client's own tickbox. pcall-guarded; when the option is
-- unavailable it defaults to shown, so a ModOptions API change can only fall back to the
-- server-wide behaviour, never hide the banner unexpectedly.
function FF.showHudTickerClient()
    if not FF.getOptions().showHudTicker then return false end   -- server hard-disabled
    local ok, val = pcall(function()
        local opt = modOptions:getOption("LasciviousFactionsSystem.showHudTicker")
        if opt == nil then return true end
        local v = opt:getValue()
        if v == nil then return true end
        return v
    end)
    if not ok then return true end
    return val and true or false
end

-- Effective in-world claim-border mode for THIS client: "off" / "near" / "on". The server
-- can hard-disable via ShowClaimBordersInWorld=false. pcall-guarded; defaults to "on".
-- True when THIS client should see every faction's claims on the map and minimap.
-- Two conditions, both re-checked live: the client is an admin, and the option is on.
-- Fails closed on any error, so a ModOptions API change can only ever take the override
-- away -- it can never leak other factions' territory to a non-admin.
-- Memoized for a second, the same TTL and reasoning as FF.getOptions: this is read
-- from map draw paths that run every frame, and resolving it means a ModOptions lookup
-- plus an access-level string compare, both of which allocate.
local seeAllCache, seeAllCacheAt = false, -1

function FF.adminSeeAllClaims()
    local now = getTimestamp and getTimestamp() or nil
    if now and seeAllCacheAt == now then return seeAllCache end

    local result = false
    if FF.isLocalAdmin and FF.isLocalAdmin() then
        local ok, val = pcall(function()
            local opt = modOptions:getOption("LasciviousFactionsSystem.adminSeeAllClaims")
            return opt and opt:getValue()
        end)
        result = (ok and val) and true or false
    end

    seeAllCache, seeAllCacheAt = result, now or -1
    return result
end

function FF.claimBorderMode()
    if not FF.getOptions().showClaimBordersInWorld then return "off" end   -- server disabled
    local ok, sel = pcall(function()
        local opt = modOptions:getOption("LasciviousFactionsSystem.claimBorderMode")
        return opt and opt:getValue()
    end)
    if not ok or not sel then return "on" end
    if sel == 3 then return "off" elseif sel == 2 then return "near" else return "on" end  -- 1 On / 2 Near / 3 Off
end

local function loadFactionModOptions()
    -- Pick up a keybind customised in a previous session; the vanilla Options
    -- screen only calls this itself when actually opened.
    PZAPI.ModOptions:load()
end
if FF._panelOptionsGameStartHook then Events.OnGameStart.Remove(FF._panelOptionsGameStartHook) end
FF._panelOptionsGameStartHook = loadFactionModOptions
Events.OnGameStart.Add(loadFactionModOptions)

local function togglePanelKey(key)
    local opt = modOptions:getOption("LasciviousFactionsSystem.togglePanel")
    if opt and key == opt.key then
        LasciviousFactionsSystemPanel.toggle()
    end
end
if FF._panelToggleKeyHook then Events.OnKeyStartPressed.Remove(FF._panelToggleKeyHook) end
FF._panelToggleKeyHook = togglePanelKey
Events.OnKeyStartPressed.Add(togglePanelKey)

-- ---------------------------------------------------------------------------
-- Persistent HUD emblem (top-right), mirrors how ISHotbar/ISChat attach directly
-- to UIManager instead of living inside another window.
-- ---------------------------------------------------------------------------
-- Only when the player has chosen the corner emblem. The default is the vanilla
-- left sidebar (LFS_VanillaUI.lua), which is where new players
-- actually look -- a floating corner button is easy to miss entirely.
local function createFactionHudIcon()
    local old = FF._panelHudIcon or LasciviousFactionsSystemPanel.hudIcon
    if old then
        pcall(function()
            old:setVisible(false)
            old:removeFromUIManager()
        end)
        FF._panelHudIcon = nil
        LasciviousFactionsSystemPanel.hudIcon = nil
    end
    if FF.hudIconPosition() ~= 2 then return end
    local size = 34
    local x = getCore():getScreenWidth() - size - 12
    local y = 12
    local icon = HudIcon:new(x, y, size, size)
    icon:initialise()
    icon:instantiate()
    icon:setVisible(true)
    icon:addToUIManager()
    FF._panelHudIcon = icon
    LasciviousFactionsSystemPanel.hudIcon = icon
end
if FF._panelHudGameStartHook then Events.OnGameStart.Remove(FF._panelHudGameStartHook) end
FF._panelHudGameStartHook = createFactionHudIcon
Events.OnGameStart.Add(createFactionHudIcon)

-- Main window's own danger-dimming primitives (see UI.installDimming's
-- comment in LFS_UI.lua). The HUD emblem button above is intentionally NOT
-- included: it lives outside the panel's child tree (added straight to
-- UIManager, visible whether or not the panel is even open), so it isn't
-- part of "the interface" this feature dims.
UI.installDimming(LasciviousFactionsSystemPanel)
