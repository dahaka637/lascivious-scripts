-- Lascivious Factions System - shared client UI toolkit.
--
-- One place for the panel's visual language: theme tokens, a per-faction colour
-- derived from the name (no server/data change), a cached texture lookup for the
-- shipped icon set, rounded-corner/shadow/animation draw helpers, and a set of
-- reusable widgets (FFButton / FFCard / FFBar / FFBadge / FFStat / FFRow /
-- FFRowGroup / FFToggle / FFSubTabs)
-- plus styleNavList(). LFS_Panel requires this file directly
-- (name-based auto-load runs alphabetically and would load "_UI" AFTER "_Panel",
-- leaving these globals nil at the panel's file scope).
--
-- The rounded/shadow/animation treatment is our own reimplementation inspired by
-- the Aegis admin panel's look -- no Aegis code or texture is imported; the
-- ui_cnr_*/ui_glow/ui_dot primitives are generated white-on-transparent PNGs
-- tinted at draw time, the same way the ic_ icon set already is.
--
-- Every widget is a real ISUIElement subclass that draws in :prerender(), so it
-- repaints every frame -- a bare drawRect/drawText outside a per-frame hook only
-- paints for one frame because the screen is fully repainted each frame.

require "LFS_Shared"
require "LFS_Localization"

local FF = LasciviousFactionsSystem

-- Idempotent: this file both auto-loads and is require'd; build the toolkit once.
if FF.UI then return end
FF.UI = {}
local UI = FF.UI

print("[LFS] ui toolkit loaded")

-- ---------------------------------------------------------------------------
-- Tokens. accent/accentDim/accentText are MUTATED in place by UI.setAccent (so
-- any spec that captured a reference to one of these tables tracks the change);
-- never replace these three tables wholesale.
-- ---------------------------------------------------------------------------
-- Server identity: deep aubergine surfaces with a vivid royal-purple accent. Faction
-- colours remain meaningful for territories, emblems and directory entries, while
-- the interface chrome stays consistently purple regardless of the current faction.
UI.color = {
    bg         = { r = 0.063, g = 0.047, b = 0.094, a = 1.00 },
    titlebar   = { r = 0.043, g = 0.031, b = 0.067, a = 1.00 },
    panel      = { r = 0.094, g = 0.067, b = 0.137, a = 1.00 }, -- sidebar / list bg
    panel2     = { r = 0.176, g = 0.125, b = 0.243, a = 1.00 }, -- hover / raised
    card       = { r = 0.129, g = 0.090, b = 0.184, a = 1.00 }, -- card fill
    cardHi     = { r = 0.208, g = 0.145, b = 0.290, a = 1.00 }, -- card hover
    border     = { r = 0.286, g = 0.208, b = 0.373, a = 1.00 },
    borderH    = { r = 0.455, g = 0.325, b = 0.604, a = 1.00 },
    accent     = { r = 0.608, g = 0.365, b = 0.898, a = 1.00 },
    accentDim  = { r = 0.239, g = 0.145, b = 0.357, a = 1.00 },
    accentText = { r = 0.898, g = 0.824, b = 1.000, a = 1.00 },
    text       = { r = 0.945, g = 0.922, b = 0.973, a = 1.00 },
    text2      = { r = 0.839, g = 0.784, b = 0.890, a = 1.00 }, -- body copy in cards
    dim        = { r = 0.635, g = 0.576, b = 0.698, a = 1.00 },
    faint      = { r = 0.475, g = 0.412, b = 0.545, a = 1.00 }, -- captions / metadata
    bad        = { r = 0.914, g = 0.396, b = 0.553, a = 1.00 },
    badDim     = { r = 0.412, g = 0.149, b = 0.231, a = 1.00 },
    badText    = { r = 1.000, g = 0.671, b = 0.757, a = 1.00 },
    good       = { r = 0.384, g = 0.831, b = 0.655, a = 1.00 },
    warn       = { r = 0.929, g = 0.690, b = 0.365, a = 1.00 },
    track      = { r = 0.286, g = 0.208, b = 0.373, a = 1.00 },
    divider    = { r = 0.157, g = 0.110, b = 0.216, a = 1.00 },
    onColor    = { r = 0.063, g = 0.035, b = 0.098, a = 1.00 }, -- text on a bright fill
    white      = { r = 1.00, g = 1.00, b = 1.00, a = 1.00 },
}

-- Fixed server-brand accent used by the interface chrome.
UI.brandAccent = { r = 0.608, g = 0.365, b = 0.898, a = 1.00 }
UI.neutralAccent = UI.brandAccent

-- Claim areas opened to everyone draw in this instead of the owner's faction colour,
-- on every surface (claim editor, world map, minimap, in-world borders). A deliberately
-- un-faction-like teal: a public area is visible to players who cannot see any of that
-- faction's other land, so it must not read as "this faction owns the ground here".
UI.publicClaimColor = { r = 0.322, g = 0.761, b = 0.765, a = 1.00 }

UI.pad = 14
UI.gap = 10

-- Claim-box rendering constants, shared by the embedded claim map and the
-- persistent world/minimap overlay so both surfaces draw claims identically.
UI.claimStyle = {
    fillAlpha    = 0.16,   -- filled interior (orthographic maps)
    borderAlpha  = 0.80,   -- rectangle border
    isoAlpha     = 0.90,   -- line alpha for the isometric quad outline
    isoThickness = 2,      -- iso line thickness on the big world map
    isoThinness  = 1,      -- iso line thickness on the small minimap
}

-- small = UIFont.NewSmall (a crisp antialiased small font), NOT UIFont.Code -- the
-- monospace bitmap Code font renders rough/faint at this scale (section headers,
-- badges, footnotes, leaderboard detail lines all read as low-quality with it).
UI.font = {
    title = UIFont.Medium,
    body  = UIFont.Small,
    small = UIFont.NewSmall,
    big   = UIFont.Large,
}

-- ---------------------------------------------------------------------------
-- Text metrics
--
-- PZ picks a font ATLAS from the player's Font Size option: 16px at the smallest
-- through 38px at the largest, and "Scale with window height" resolves to the 38px
-- set on anything 1872px tall or more. So on a 4K screen every font in this toolkit
-- is roughly 2.4x the height it is at the default -- which is what broke the panel
-- before 1.2.10, when every vertical measurement here was a hardcoded literal while
-- every horizontal one was measured.
--
-- THE RULE, and the reason the panel is not broken any more: a height derives from
-- UI.fh() if and only if the thing it measures CONTAINS TEXT. Bars, status dots,
-- colour swatches, corner radii, icon sizes and hairlines contain none and stay
-- literal -- as do all GAPS between elements, which is what vanilla does too
-- (UI_BORDER_SPACING = 10 is a constant in every ISUI file).
-- ---------------------------------------------------------------------------

-- Font heights never change inside a Lua session: the only thing that rebuilds the
-- atlas is TextManager.Init(), and every caller of that immediately reloads all Lua
-- (which is precisely why the Font Size option warns it needs a restart in-game).
-- So there is nothing to invalidate, and memoizing turns a per-frame java call --
-- this is called dozens of times per frame across the prerenders -- into a lookup.
local fhCache = {}

-- Test-only multiplier, driven by `/ff admin uitest`. Left OUT of the cache so the
-- scaled pass can never poison the real metrics. See LFS_UiTest.lua.
UI.fhScale = 1

function UI.fh(font)
    font = font or UI.font.body
    local raw = fhCache[font]
    if not raw then
        raw = getTextManager():getFontHeight(font)
        fhCache[font] = raw
    end
    if UI.fhScale ~= 1 then return math.floor(raw * UI.fhScale) end
    return raw
end

-- Measured widths are memoized for the same reason font heights are: the atlas is
-- fixed for a Lua session, so a (font, string) pair always measures the same. The
-- difference is volume -- UI.tw is called from a dozen prerenders, and UI.fit below
-- can call it once PER CHARACTER on an overflowing string, so a single long faction
-- name or MOTD used to cost dozens of java calls per frame.
--
-- Bounded rather than unbounded: some measured strings are live text (countdowns,
-- balances, search input) whose keys never repeat. Past TW_CACHE_MAX the whole table
-- is dropped and refills -- a periodic rebuild of the handful of hot entries, which is
-- cheaper and far simpler than tracking recency.
-- Two levels (font -> string -> width) rather than a concatenated key: a UIFont is a
-- java enum, so it keys a table by identity the way fhCache already does, but it will
-- not concatenate into a string.
local twCache, twCacheN = {}, 0
local TW_CACHE_MAX = 4096

function UI.tw(font, s)
    font = font or UI.font.body
    s = s or ""
    local byFont = twCache[font]
    if byFont then
        local hit = byFont[s]
        if hit then return hit end
    else
        byFont = {}
        twCache[font] = byFont
    end
    local w = getTextManager():MeasureStringX(font, s)
    if twCacheN >= TW_CACHE_MAX then
        twCache, twCacheN = {}, 0
        byFont = {}
        twCache[font] = byFont
    end
    byFont[s], twCacheN = w, twCacheN + 1
    return w
end

-- Vertical counterparts to UI.tw / UI.buttonWidth / UI.chipWidth. The pads below are
-- reverse-engineered from the literals this file used before 1.2.10, so at the
-- default atlas they reproduce the old layout exactly rather than nudging every
-- player's panel: with fh(Small)=18 and fh(NewSmall)=14 they give rowH(body)=30
-- (FFButton), rowH(small)=26 (RolePermRow), cardTop()=26 (card content top),
-- badgeH()=18 (FFBadge), lineH(body)=22 (the old stat-row pitch) and lineH(small)=18
-- (the old card text pitch). `/ff admin uitest` prints the real heights, so if PZ's
-- actual values differ the pads can be retuned against evidence.

-- Pitch between consecutive lines of text.
function UI.lineH(font) return UI.fh(font) + 4 end

-- Height of a control that holds one line of text (button, entry, toggle, row).
function UI.rowH(font) return UI.fh(font) + 12 end

-- First content y inside an FFCard, clear of the title FFCard:prerender draws at y=8.
function UI.cardTop() return 8 + UI.fh(UI.font.small) + 4 end

-- Total height of a card whose last child ends at `bottom`.
function UI.cardH(bottom) return bottom + 8 end

-- Height of an FFBadge pill.
function UI.badgeH() return UI.fh(UI.font.small) + 4 end

-- Trim `s` so it fits inside maxW pixels, appending an ellipsis when it had to be
-- cut. Guards any fixed-width box against a long label; callers can retune the text
-- itself without risking overflow.
-- Greedy word-wrap to a pixel width, measured with the same font metrics the widgets
-- draw with (UI.tw). Returns a list of lines. A single word wider than maxW is left to
-- overflow rather than hard-split (fine for MOTD / help / explanatory copy).
--
-- Lives here rather than in the panel because the stall window needs it too, and a
-- second copy would be one more thing to keep in step with UI.tw.
function UI.wrapText(text, font, maxW)
    local lines = {}
    local cur = ""
    for word in string.gmatch(tostring(text or ""), "%S+") do
        local try = (cur == "") and word or (cur .. " " .. word)
        if cur ~= "" and UI.tw(font, try) > maxW then
            lines[#lines + 1] = cur
            cur = word
        else
            cur = try
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

function UI.fit(font, s, maxW)
    s = s or ""
    if maxW <= 0 or UI.tw(font, s) <= maxW then return s end
    local ellipsis = "..."
    local budget = maxW - UI.tw(font, ellipsis)
    if budget <= 0 then return ellipsis end
    -- Binary search rather than a linear walk-back. The walk-back was chosen on the
    -- assumption that overflow is usually near-fit, but the strings that actually
    -- overflow are the long ones -- a MOTD or a description in a narrow card -- where
    -- it measured once per character trimmed, every frame, from inside a prerender.
    -- Worst case is now ~log2(#s) measurements instead of ~#s.
    local lo, hi, best = 1, #s - 1, nil
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local cut = string.sub(s, 1, mid)
        if UI.tw(font, cut) <= budget then
            best = cut
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    if best then return best .. ellipsis end
    return ellipsis
end

-- Natural width of an FFButton carrying `label` -- text plus the icon block plus
-- the 8px side padding :prerender() reserves. Lets a control row be laid out from
-- measured text instead of hardcoded widths, so it survives a different UI scale,
-- a longer toggle state ("Erasing..."), or a translation.
function UI.buttonWidth(label, hasIcon, height, font)
    label = FF.tr and FF.tr(label) or label
    local h = height or UI.rowH(font or UI.font.body)
    local iconSize = hasIcon and (h - 12) or 0
    local iconGap = hasIcon and 6 or 0
    return math.ceil(UI.tw(font or UI.font.body, label or "") + iconSize + iconGap + 16)
end

-- ---------------------------------------------------------------------------
-- Per-faction colour: stable name hash -> hue, fixed S/V tuned to read on the
-- dark UI. Pure Lua, deterministic, no data-model change.
-- ---------------------------------------------------------------------------
function UI.hsv(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    local r, g, b
    if     i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else               r, g, b = v, p, q end
    return { r = r, g = g, b = b, a = 1 }
end

-- Memoized, 1s TTL, keyed by name. Every call is a registry lookup plus a hash over
-- the name plus a fresh table, and it runs per territory and per member on the map
-- overlay -- every frame, with the minimap always on. The TTL is what keeps the
-- Settings-tab colour override applying live without a restart, the same trade
-- FF.getOptions makes.
--
-- The returned table is SHARED -- treat it as read-only. UI.setAccent copies the
-- components out rather than keeping the table, and the draw helpers only read.
local colorCache, colorCacheAt = {}, -1
local COLOR_TTL = 1

function UI.factionColor(name)
    local now = getTimestamp and getTimestamp() or nil
    if now then
        if (now - colorCacheAt) >= COLOR_TTL then
            colorCache, colorCacheAt = {}, now
        end
        local hit = colorCache[name or ""]
        if hit then return hit end
    end
    local c = UI.computeFactionColor(name)
    if now then colorCache[name or ""] = c end
    return c
end

function UI.computeFactionColor(name)
    -- Explicit owner-chosen override (set via the Settings tab) wins over the
    -- name-derived colour, so every caller (header, HUD emblem, claim-map fill)
    -- picks it up centrally.
    local faction = FF.getFaction and FF.getFaction(name)
    if faction and faction.color then
        local c = faction.color
        return { r = c.r, g = c.g, b = c.b, a = 1 }
    end
    name = tostring(name or "")
    local h = 5381
    for i = 1, #name do
        h = (h * 33 + name:byte(i)) % 2147483648
    end
    return UI.hsv((h % 360) / 360, 0.55, 0.85)
end

-- Up to two initials from a faction name, for the emblem square.
local function utf8Prefix(text, count)
    local pos, finish = 1, 0
    for _ = 1, count do
        local byte = string.byte(text, pos)
        if not byte then break end
        local width = (byte < 0x80 and 1)
            or (byte < 0xE0 and 2)
            or (byte < 0xF0 and 3)
            or 4
        finish = math.min(#text, pos + width - 1)
        pos = finish + 1
    end
    return string.sub(text, 1, finish)
end

function UI.initials(name)
    name = tostring(name or "?")
    local parts = {}
    for w in name:gmatch("%S+") do parts[#parts + 1] = w end
    local s
    if #parts >= 2 then s = utf8Prefix(parts[1], 1) .. utf8Prefix(parts[2], 1)
    elseif #parts == 1 then s = utf8Prefix(parts[1], 2)
    else s = "?" end
    -- string.upper changes ASCII letters and leaves the already-complete UTF-8
    -- sequences intact. Most importantly, the prefix helper never slices an accented
    -- character in half, which used to render as a replacement glyph.
    return string.upper(s)
end

-- Capacity bar colour: green while there's headroom, amber near the cap, red at it.
function UI.barColor(frac)
    if frac >= 0.9 then return UI.color.bad
    elseif frac >= 0.7 then return UI.color.warn
    else return UI.color.good end
end

-- Perceived luminance -> pick dark or light text/icon that reads on a fill.
function UI.readableOn(c)
    local lum = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    if lum > 0.55 then return UI.color.onColor else return UI.color.text end
end

-- ---------------------------------------------------------------------------
-- Per-faction accent. Mutates the three accent tables in place so BTN specs and
-- any captured references track the new colour. Call before (re)building a
-- section; pass nil for the neutral steel fallback.
-- ---------------------------------------------------------------------------
function UI.setAccent(base)
    base = base or UI.neutralAccent
    local a = UI.color.accent
    a.r, a.g, a.b = base.r, base.g, base.b
    local ad = UI.color.accentDim
    ad.r, ad.g, ad.b = base.r * 0.4, base.g * 0.4, base.b * 0.4
    local at = UI.color.accentText
    at.r = math.min(1, base.r * 0.25 + 0.75)
    at.g = math.min(1, base.g * 0.25 + 0.75)
    at.b = math.min(1, base.b * 0.25 + 0.75)
end

-- ---------------------------------------------------------------------------
-- Icon / primitive texture cache. White source PNGs tinted at draw time via
-- drawTextureScaled, so one file serves every colour/state. nil-safe: a missing
-- file degrades to "no texture" instead of erroring. The ui_* primitives live in
-- the same directory as the ic_* icons, so this cache serves both.
-- ---------------------------------------------------------------------------
UI.iconDir = "media/textures/LasciviousFactionsSystem/"
local iconCache = {}
function UI.icon(name)
    if not name then return nil end
    local cached = iconCache[name]
    if cached ~= nil then return cached or nil end
    local tex = getTexture(UI.iconDir .. name .. ".png")
    iconCache[name] = tex or false
    return tex
end

-- Draw a cached icon tinted to a colour table. No-op if the texture is missing.
-- `alpha` is an optional multiplier on the colour's own alpha, so a caller can dim a
-- whole widget without having to clone its colour table (the HUD button uses it to
-- fade with the vanilla sidebar). Omitted, behaviour is exactly as before.
function UI.drawIcon(self, name, x, y, size, color, alpha)
    local tex = UI.icon(name)
    if not tex then return false end
    color = color or UI.color.text
    local a = (color.a or 1) * (alpha or 1)
    self:drawTextureScaled(tex, x, y, size, size, a, color.r, color.g, color.b)
    return true
end

-- ---------------------------------------------------------------------------
-- Rounded-corner / shadow / hairline draw helpers. Corners are quarter-disc
-- masks (ui_cnr_*) drawn at r x r into each corner, with the straight edges
-- filled by plain rects. Degrades to a square drawRect if the corner textures
-- are missing, so nothing ever leaves a hole.
-- ---------------------------------------------------------------------------
function UI.roundRect(el, x, y, w, h, r, a, c)
    x, y, w, h = math.floor(x), math.floor(y), math.floor(w), math.floor(h)
    local half = math.floor(math.min(w, h) / 2)
    if r > half then r = half end
    local tl = r >= 1 and UI.icon("ui_cnr_tl") or nil
    if not tl then
        el:drawRect(x, y, w, h, a, c.r, c.g, c.b)
        return
    end
    el:drawTextureScaled(tl, x, y, r, r, a, c.r, c.g, c.b)
    el:drawTextureScaled(UI.icon("ui_cnr_tr"), x + w - r, y, r, r, a, c.r, c.g, c.b)
    el:drawTextureScaled(UI.icon("ui_cnr_bl"), x, y + h - r, r, r, a, c.r, c.g, c.b)
    el:drawTextureScaled(UI.icon("ui_cnr_br"), x + w - r, y + h - r, r, r, a, c.r, c.g, c.b)
    if w > 2 * r then
        el:drawRect(x + r, y, w - 2 * r, r, a, c.r, c.g, c.b)
        el:drawRect(x + r, y + h - r, w - 2 * r, r, a, c.r, c.g, c.b)
    end
    if h > 2 * r then
        el:drawRect(x, y + r, w, h - 2 * r, a, c.r, c.g, c.b)
    end
end

-- Rounded frame: border colour underneath, fill inset by 1px on top.
-- A nil cFill draws the ring alone, leaving whatever is underneath showing through --
-- which is the only way to put an outlined pill on a card without knowing the card's
-- ground colour. With a fill it is the usual border-plus-body frame.
function UI.roundFrame(el, x, y, w, h, r, a, cBorder, cFill)
    UI.roundRect(el, x, y, w, h, r, a, cBorder)
    if cFill then
        UI.roundRect(el, x + 1, y + 1, w - 2, h - 2, math.max(1, r - 1), a, cFill)
    end
end

-- Soft drop shadow behind a rect (ui_glow tinted black, stretched + offset down).
function UI.shadow(el, x, y, w, h, spread, a)
    local t = UI.icon("ui_glow")
    if t then
        el:drawTextureScaled(t, x - spread, y - spread + 5, w + spread * 2, h + spread * 2, a or 0.5, 0, 0, 0)
    end
end

function UI.hairline(el, x, y, w, a, c)
    c = c or UI.color.border
    el:drawRect(x, y, w, 1, a or 1, c.r, c.g, c.b)
end

-- ---------------------------------------------------------------------------
-- Framerate-independent animation. delta() normalises the frame time to 30fps
-- (capped so a stutter can't teleport), glide() eases a value toward a target.
-- ---------------------------------------------------------------------------
function UI.delta()
    local d = UIManager.getMillisSinceLastRender() / 33.3
    if d > 3 then d = 3 end
    return d
end

function UI.glide(cur, target, rate)
    local t = rate * UI.delta()
    if t > 1 then t = 1 end
    local v = cur + (target - cur) * t
    if math.abs(target - v) < 0.002 then return target end
    return v
end

-- ===========================================================================
-- FFButton : ISButton -- themed variants (primary / danger / ghost), rounded,
-- hover-glide + press feedback, optional leading icon. Inherits ISButton's click
-- handling. primary fills with the (per-faction) accent; text auto-contrasts.
-- ===========================================================================
FFButton = ISButton:derive("FFButton")

function FFButton:new(x, y, width, height, title, target, onclick, variant, iconName)
    title = FF.tr(title)
    -- nil height = "one line of body text": the default UI.buttonWidth also assumes,
    -- so the two can never disagree and clip the label.
    local o = ISButton:new(x, y, width, height or UI.rowH(UI.font.body), title, target, onclick)
    setmetatable(o, self)
    self.__index = self
    o.variant = variant or "ghost"
    o.iconName = iconName
    o.font = UI.font.body
    o.radius = 8
    o.hoverT = 0
    -- Neutralise the stock ISButton look; we draw everything in :prerender().
    o.borderColor = UI.color.border
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
    return o
end

function FFButton:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    local enabled = self:isEnabled()
    local hover = enabled and self:isMouseOver()
    local pressed = enabled and self.pressed
    self.hoverT = UI.glide(self.hoverT or 0, hover and 1 or 0, 0.35)
    local r = math.min(self.radius or 8, math.floor(h / 2))
    local a = enabled and 1 or 0.4
    local ht = self.hoverT
    local textC, iconC

    if not enabled and self.disabledNeutral then
        -- Some disabled actions communicate a hard prerequisite rather than a
        -- temporary selection state. Render those unmistakably neutral/grey instead
        -- of leaving a translucent version of the primary accent on screen.
        UI.roundFrame(self, 0, 0, w, h, r, 0.85, c.border, c.card)
        textC = c.dim; iconC = c.dim
        a = 0.75
    elseif self.variant == "primary" then
        -- `tint` lets a caller give one primary button its own colour without a whole
        -- new variant -- used by the shop-claim button so it carries the same teal as
        -- every other public-area affordance. Defaults to the theme accent.
        local fill = self.tint or c.accent
        UI.roundRect(self, 0, 0, w, h, r, a, fill)
        if ht > 0.01 then UI.roundRect(self, 0, 0, w, h, r, 0.16 * ht * a, c.white) end
        if pressed then UI.roundRect(self, 0, 0, w, h, r, 0.20, c.onColor) end
        textC = UI.readableOn(fill); iconC = textC
    elseif self.variant == "danger" then
        UI.roundFrame(self, 0, 0, w, h, r, a, c.bad, c.bg)
        if ht > 0.01 then UI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.16 * ht * a, c.bad) end
        if pressed then UI.roundRect(self, 0, 0, w, h, r, 0.20, c.bad) end
        textC = c.badText; iconC = c.bad
    else -- ghost
        local bc = hover and c.borderH or c.border
        UI.roundFrame(self, 0, 0, w, h, r, a, bc, c.card)
        if ht > 0.01 then UI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.6 * ht * a, c.cardHi) end
        if pressed then UI.roundRect(self, 1, 1, w - 2, h - 2, math.max(1, r - 1), 0.25, c.onColor) end
        textC = c.text; iconC = (hover and c.accent or c.dim)
    end
    if not enabled then textC = c.dim; iconC = c.dim end

    local iconSize = self.iconName and (h - 12) or 0
    local iconGap = self.iconName and 6 or 0
    -- Clip the label to the button rect: startX floors at 8, so an oversized title
    -- would otherwise paint straight out over whatever sits to the right.
    local label = UI.fit(self.font, self.title or "", w - 16 - iconSize - iconGap)
    local textW = UI.tw(self.font, label)
    -- An icon button carries no label, so the gap after the icon is phantom width and
    -- would push the glyph off-centre by half of it. Drop it when there is no text.
    if label == "" then iconGap = 0 end
    local total = iconSize + iconGap + textW
    local startX = math.max(8, math.floor((w - total) / 2))
    local cy = math.floor((h - UI.fh(self.font)) / 2)
    if self.iconName then
        UI.drawIcon(self, self.iconName, startX, math.floor((h - iconSize) / 2), iconSize, iconC)
    end
    self:drawText(label, startX + iconSize + iconGap, cy, textC.r, textC.g, textC.b, a, self.font)
end

-- Suppress ISButton's own title/image drawing; :prerender() does it all.
function FFButton:render() end

-- A square, label-less FFButton carrying only an icon. The design system uses these
-- wherever a row already says what the thing is and the control only needs to say
-- what it DOES -- "show on map" next to a shop name, say, where a 118px text button
-- would out-shout the shop it belongs to. Square, so a run of them lines up down the
-- right edge of a list.
--
-- The side is derived: it holds no text, but it has to match the height of the text
-- controls it sits beside, and those grow with the font atlas.
function UI.iconButtonSize() return UI.rowH(UI.font.body) end

function UI.iconButton(x, y, iconName, target, onclick, variant)
    local sz = UI.iconButtonSize()
    local b = FFButton:new(x, y, sz, sz, "", target, onclick, variant or "ghost", iconName)
    b.isIconOnly = true
    return b
end

-- ===========================================================================
-- FFCard : ISPanel -- rounded bordered surface with an optional dim title row
-- and an optional soft shadow. A plain container; callers add children at
-- coordinates relative to the card.
-- ===========================================================================
FFCard = ISPanel:derive("FFCard")

function FFCard:new(x, y, width, height, title)
    title = FF.tr(title)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.title = title
    o.shadow = false
    -- 8, not 10: --radius-md in the design system the panel is built from.
    o.radius = 8
    -- The card title is the design system's "kicker" -- small, uppercase, and ACCENT
    -- coloured by default rather than dim, which is what makes a wall of cards
    -- scannable. Individual cards override it to say something about their content:
    -- warn on Progression, bad on Settings' danger zone.
    o.kickerColor = nil
    return o
end

-- Where a card's first child goes: clear of the title drawn at y=8 by :prerender(),
-- or a plain inset when the card has no title.
function FFCard:contentTop()
    return self.title and UI.cardTop() or 12
end

-- Size the card to content once its children are placed -- the vanilla ISTextBox
-- idiom (build on a running y, set the container height last). Callers that use this
-- pass 0 as the constructor height; that is safe because :prerender() cannot run
-- before the synchronous build finishes.
function FFCard:setContentHeight(bottom)
    self:setHeight(UI.cardH(bottom))
    return self:getHeight()
end

function FFCard:prerender()
    local w, h = self:getWidth(), self:getHeight()
    local c = UI.color
    if self.shadow then UI.shadow(self, 0, 0, w, h, 16, 0.35) end
    UI.roundFrame(self, 0, 0, w, h, self.radius, 1.0, c.border, c.panel)
    if self.title then
        local k = self.kickerColor or c.accent
        self:drawText(self.title, 12, 8, k.r, k.g, k.b, 1.0, UI.font.small)
    end
end

-- ===========================================================================
-- FFBar : ISPanel -- rounded capacity/progress bar with a track, state colour,
-- and an optional centred label. Set .fraction (0..1), .color (override), .label.
-- ===========================================================================
FFBar = ISPanel:derive("FFBar")

function FFBar:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.fraction = 0
    o.color = nil
    o.label = nil
    return o
end

function FFBar:prerender()
    local w, h = self:getWidth(), self:getHeight()
    local c = UI.color
    local r = math.min(math.floor(h / 2), 6)
    UI.roundRect(self, 0, 0, w, h, r, 1.0, c.track)
    local frac = math.max(0, math.min(1, self.fraction or 0))
    local fillW = math.floor((w - 2) * frac)
    local col = self.color or UI.barColor(frac)
    if fillW > 0 then
        UI.roundRect(self, 1, 1, math.max(2 * r, fillW), h - 2, math.max(1, r - 1), 1.0, col)
    end
    if self.label then
        self:drawTextCentre(self.label, math.floor(w / 2), math.floor((h - UI.fh(UI.font.small)) / 2),
            c.text.r, c.text.g, c.text.b, 1.0, UI.font.small)
    end
end

-- ===========================================================================
-- FFBadge : ISPanel -- small rounded pill (tag / role) tinted from a fill
-- colour, with an optional leading icon. Width auto-sizes to its text.
-- ===========================================================================
FFBadge = ISPanel:derive("FFBadge")

function FFBadge:new(x, y, text, opts)
    text = FF.tr(text)
    opts = opts or {}
    local font = UI.font.small
    local iconW = opts.icon and 14 or 0
    local width = UI.tw(font, text) + 16 + iconW
    local height = UI.badgeH()
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.text = text
    o.font = font
    o.icon = opts.icon
    o.fill = opts.fill or UI.color.accent
    -- Outline variant (the design system's .tag-outline): a hairline ring instead of a
    -- tinted ground. Reads as a property of the thing rather than a status ON it, which
    -- is why the playstyle tags on a recruit profile use it and the role pills do not.
    o.outline = opts.outline and true or false
    return o
end

function FFBadge:prerender()
    local w, h = self:getWidth(), self:getHeight()
    local f = self.fill
    if self.outline then
        UI.roundFrame(self, 0, 0, w, h, math.floor(h / 2), 1.0, f, nil)
    else
        UI.roundRect(self, 0, 0, w, h, math.floor(h / 2), 0.20, f)
    end
    local x = 8
    if self.icon then
        local isz = math.min(12, h - 6)
        UI.drawIcon(self, self.icon, x, math.floor((h - isz) / 2), isz, f)
        x = x + 14
    end
    self:drawText(self.text, x, math.floor((h - UI.fh(self.font)) / 2), f.r, f.g, f.b, 1.0, self.font)
end

-- ===========================================================================
-- FFToggle : ISPanel -- sliding on/off switch with a label on the left and an
-- animated knob on the right. onChange(target, checked, self).
-- ===========================================================================
FFToggle = ISPanel:derive("FFToggle")

function FFToggle:new(x, y, width, height, label, target, onChange)
    label = FF.tr(label)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.label = label
    o.target = target
    o.onChange = onChange
    o.checked = false
    o.knobT = 0
    o.hovered = false
    o.enabled = true
    o.pressed = false
    o.font = UI.font.body
    return o
end

function FFToggle:setChecked(b) self.checked = b and true or false end
function FFToggle:setEnabled(b)
    self.enabled = b and true or false
    if not self.enabled then self.pressed = false end
end
function FFToggle:isChecked() return self.checked end

function FFToggle:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    local a = self.enabled and 1 or 0.4
    self.knobT = UI.glide(self.knobT, self.checked and 1 or 0, 0.3)

    local labelC = (self.checked and c.text or c.dim)
    if self.hovered and self.enabled then labelC = c.text end
    self:drawText(self.label or "", 0, math.floor((h - UI.fh(self.font)) / 2), labelC.r, labelC.g, labelC.b, a, self.font)

    local tw, th = 38, 20
    local sx = w - tw
    local sy = math.floor((h - th) / 2)
    UI.roundRect(self, sx, sy, tw, th, math.floor(th / 2), a, c.track)
    if self.knobT > 0.01 then
        UI.roundRect(self, sx, sy, tw, th, math.floor(th / 2), self.knobT * a, c.accent)
    end
    local kd = th - 6
    local kx = sx + 3 + (tw - 6 - kd) * self.knobT
    local dot = UI.icon("ui_dot")
    if dot then
        local kc = self.knobT > 0.5 and UI.readableOn(c.accent) or c.text
        self:drawTextureScaled(dot, kx, sy + 3, kd, kd, a, kc.r, kc.g, kc.b)
    else
        local kc = self.knobT > 0.5 and UI.readableOn(c.accent) or c.text
        self:drawRect(kx, sy + 3, kd, kd, a, kc.r, kc.g, kc.b)
    end
end

function FFToggle:onMouseMove() self.hovered = true end
function FFToggle:onMouseMoveOutside() self.hovered = false end
function FFToggle:onMouseDown() if self.enabled then self.pressed = true end end
function FFToggle:onMouseUpOutside() self.pressed = false end
function FFToggle:onMouseUp()
    if not self.pressed or not self.enabled then self.pressed = false return end
    self.pressed = false
    self.checked = not self.checked
    getSoundManager():playUISound("UIActivateButton")
    if self.onChange then self.onChange(self.target, self.checked, self) end
end

-- ===========================================================================
-- FFStat : ISPanel -- the design system's stat tile: a small uppercase kicker, a
-- large value, and either a sub-line or a progress bar underneath.
--
-- This is the element that carries the redesign. The panel used to state its numbers
-- as "Members: 5" label/value rows, which reads as a form -- every figure the same
-- weight, nothing to catch the eye. A tile makes the NUMBER the thing you see and
-- demotes its name to a caption, so a row of three answers "how are we doing" at a
-- glance instead of on a read.
--
-- One honest limitation: the source design pairs a 30px value with an 11px kicker,
-- roughly 3:1. PZ exposes four fonts, and Large against NewSmall is about 2:1, so the
-- contrast is real but gentler than the mockup. Nothing to fix -- there is no larger
-- font to reach for.
-- ===========================================================================
FFStat = ISPanel:derive("FFStat")

-- Bar and its gap contain no text, so they stay literal (see THE RULE above).
local STAT_BAR_H = 8

-- Height of a tile: card padding, kicker line, value line, then either a sub-line or
-- a bar. Derived, so the tile grows with the player's font atlas instead of clipping.
function FFStat.selfHeight(hasFoot)
    local h = 12 + UI.lineH(UI.font.small) + UI.fh(UI.font.big) + 2
    if hasFoot then h = h + 6 + UI.lineH(UI.font.small) end
    return h + 12
end

-- opts: { kicker, value, valueSuffix, sub, fraction, barColor, valueColor, valueFn }
-- `sub` and `fraction` are alternatives -- pass one. valueSuffix is drawn small and
-- dim directly after the value ("694 / 4,900 tiles", "$12.40 /payout").
--
-- valueFn re-reads the value every frame instead of using the built-in one, for any
-- tile whose figure can change between registry syncs and needs to stay live.
function FFStat:new(x, y, width, opts)
    opts = opts or {}
    local hasFoot = (opts.sub ~= nil) or (opts.fraction ~= nil)
    local o = ISPanel:new(x, y, width, FFStat.selfHeight(hasFoot))
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.kicker = FF.tr(opts.kicker)
    o.value = FF.tr(opts.value)
    o.valueSuffix = FF.tr(opts.valueSuffix)
    o.sub = FF.tr(opts.sub)
    o.fraction = opts.fraction
    o.barColor = opts.barColor
    o.valueColor = opts.valueColor
    o.valueFn = opts.valueFn
    return o
end

function FFStat:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    UI.roundFrame(self, 0, 0, w, h, 8, 1.0, c.border, c.panel)

    local y = 12
    if self.kicker then
        self:drawText(UI.fit(UI.font.small, self.kicker, w - 24), 12, y,
            c.dim.r, c.dim.g, c.dim.b, 1.0, UI.font.small)
    end
    y = y + UI.lineH(UI.font.small)

    local vc = self.valueColor or c.text
    local value = self.value
    if self.valueFn then
        -- Guarded: this may read an optional third-party mod's API every frame, and a
        -- change there must degrade to a dash rather than error 60x/second.
        local ok, v = pcall(self.valueFn)
        value = ok and v or "-"
    end
    value = tostring(value or "")
    self:drawText(UI.fit(UI.font.big, value, w - 24), 12, y, vc.r, vc.g, vc.b, 1.0, UI.font.big)
    if self.valueSuffix then
        -- Baseline-aligned with the value rather than top-aligned, so "/ 4,900 tiles"
        -- sits with the number instead of floating above it.
        local vx = 12 + UI.tw(UI.font.big, value) + 6
        local vy = y + UI.fh(UI.font.big) - UI.fh(UI.font.small) - 2
        if vx < w - 12 then
            self:drawText(UI.fit(UI.font.small, self.valueSuffix, w - 12 - vx), vx, vy,
                c.dim.r, c.dim.g, c.dim.b, 1.0, UI.font.small)
        end
    end
    y = y + UI.fh(UI.font.big) + 2

    if self.fraction then
        local by = y + 6
        UI.roundRect(self, 12, by, w - 24, STAT_BAR_H, 4, 1.0, c.track)
        local f = math.max(0, math.min(1, self.fraction))
        local fw = math.floor((w - 24) * f)
        if fw > 0 then
            local bc = self.barColor or UI.barColor(f)
            UI.roundRect(self, 12, by, math.max(STAT_BAR_H, fw), STAT_BAR_H, 4, 1.0, bc)
        end
    elseif self.sub then
        self:drawText(UI.fit(UI.font.small, self.sub, w - 24), 12, y + 6,
            c.dim.r, c.dim.g, c.dim.b, 1.0, UI.font.small)
    end
end

-- ===========================================================================
-- FFRow : ISPanel -- one line of a list: an optional initial-square avatar, a title
-- with a dim sub-line under it, and a right-hand slot for a badge or a button.
--
-- Rows are stacked inside an FFRowGroup so a list reads as a single card with
-- separators, which is what makes the redesign's lists scan as content rather than
-- as a table. Rows are real widgets, so the right slot can hold a live control --
-- that is the difference from the old custom-drawn ISScrollingListBox rows, which
-- could only ever paint text.
-- ===========================================================================
FFRow = ISPanel:derive("FFRow")

function FFRow.selfHeight(hasSub)
    local textH = UI.fh(UI.font.body) + (hasSub and (2 + UI.fh(UI.font.small)) or 0)
    -- Floor of rowH so a row with no sub-line still has a comfortable target.
    return math.max(UI.rowH(UI.font.body), textH + 20)
end

-- opts: { title, sub, avatar (string -> initials+colour), avatarColor, icon,
--         badge (FFBadge, added as a child), onClick, target, dim }
function FFRow:new(x, y, width, opts)
    opts = opts or {}
    local o = ISPanel:new(x, y, width, FFRow.selfHeight(opts.sub ~= nil))
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.title = FF.tr(opts.title)
    o.sub = FF.tr(opts.sub)
    o.avatar = opts.avatar
    o.avatarColor = opts.avatarColor
    o.icon = opts.icon
    o.onClick = opts.onClick
    o.target = opts.target
    o.dim = opts.dim and true or false
    o.selected = false
    o.hoverT = 0
    o.rightW = 0        -- reserved by addRight(); keeps the title from running under it
    return o
end

-- Park a widget in the row's right-hand slot, vertically centred, and reserve its
-- width so :prerender's text fitting stops short of it.
function FFRow:addRight(el, gap)
    el:setX(self:getWidth() - el:getWidth() - 12)
    el:setY(math.floor((self:getHeight() - el:getHeight()) / 2))
    self:addChild(el)
    self.rightW = self.rightW + el:getWidth() + (gap or 10)
    return el
end

function FFRow:avatarSize() return UI.fh(UI.font.body) + 10 end

function FFRow:onMouseDown(x, y)
    if not self.onClick then return false end
    self.onClick(self.target, self)
    return true
end

function FFRow:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    local hover = self.onClick and self:isMouseOver()
    self.hoverT = UI.glide(self.hoverT or 0, hover and 1 or 0, 0.35)
    if self.selected then
        UI.roundRect(self, 0, 0, w, h, 6, 1.0, c.panel2)
    elseif self.hoverT > 0.01 then
        UI.roundRect(self, 0, 0, w, h, 6, self.hoverT * 0.7, c.cardHi)
    end

    local x = 12
    if self.avatar then
        local sz = self:avatarSize()
        local ac = self.avatarColor or UI.factionColor(self.avatar)
        local ay = math.floor((h - sz) / 2)
        UI.roundRect(self, x, ay, sz, sz, 6, 1.0, ac)
        local on = UI.readableOn(ac)
        self:drawTextCentre(UI.initials(self.avatar), x + math.floor(sz / 2),
            ay + math.floor((sz - UI.fh(UI.font.small)) / 2),
            on.r, on.g, on.b, 1.0, UI.font.small)
        x = x + sz + 10
    elseif self.icon then
        local isz = 16
        UI.drawIcon(self, self.icon, x, math.floor((h - isz) / 2), isz, c.dim)
        x = x + isz + 10
    end

    local budget = w - x - 12 - self.rightW
    local tc = self.dim and c.dim or c.text
    if self.sub then
        local blockH = UI.fh(UI.font.body) + 2 + UI.fh(UI.font.small)
        local ty = math.floor((h - blockH) / 2)
        self:drawText(UI.fit(UI.font.body, self.title or "", budget), x, ty,
            tc.r, tc.g, tc.b, 1.0, UI.font.body)
        self:drawText(UI.fit(UI.font.small, self.sub, budget), x, ty + UI.fh(UI.font.body) + 2,
            c.faint.r, c.faint.g, c.faint.b, 1.0, UI.font.small)
    else
        self:drawText(UI.fit(UI.font.body, self.title or "", budget), x,
            math.floor((h - UI.fh(UI.font.body)) / 2), tc.r, tc.g, tc.b, 1.0, UI.font.body)
    end
end

-- ===========================================================================
-- FFRowGroup : ISPanel -- a bordered container that stacks FFRows with hairline
-- separators, so a run of rows reads as one card rather than as loose strips.
-- Build with :add(row) and finish with :seal(); the group sizes itself.
-- ===========================================================================
FFRowGroup = ISPanel:derive("FFRowGroup")

function FFRowGroup:new(x, y, width)
    local o = ISPanel:new(x, y, width, 0)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.rows = {}
    o.nextY = 0
    return o
end

function FFRowGroup:add(row)
    row:setX(0)
    row:setY(self.nextY)
    row:setWidth(self:getWidth())
    self.rows[#self.rows + 1] = row
    self.nextY = self.nextY + row:getHeight()
    self:addChild(row)
    return row
end

-- Call once every row is added. Returns the final height so the caller can advance
-- its own running y, the same contract FFCard:setContentHeight has.
function FFRowGroup:seal()
    self:setHeight(math.max(1, self.nextY))
    return self:getHeight()
end

function FFRowGroup:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    UI.roundFrame(self, 0, 0, w, h, 8, 1.0, c.border, c.panel)
    -- Separators between rows, not above the first or below the last.
    for i = 2, #self.rows do
        UI.hairline(self, 10, self.rows[i]:getY(), w - 20, 1.0, c.divider)
    end
end

-- ===========================================================================
-- Status chip -- a small outlined pill used by the panel's always-visible status
-- strip. A draw helper rather than a widget: the strip repaints inside the
-- window's own :prerender() and its contents change every frame (countdowns,
-- war scores), so there is nothing worth keeping as a child element.
-- Returns the width consumed, so callers can lay several out left-to-right.
-- ===========================================================================
function UI.chipWidth(text) return UI.tw(UI.font.small, text) + 20 end

function UI.chipHeight() return UI.fh(UI.font.small) + 6 end

function UI.chip(el, x, y, h, text, color)
    local c = color or UI.color.dim
    h = h or UI.chipHeight()
    local w = UI.chipWidth(text)
    UI.roundFrame(el, x, y, w, h, 6, 1.0, c, UI.color.bg)
    el:drawText(text, x + 10, y + math.floor((h - UI.fh(UI.font.small)) / 2),
        c.r, c.g, c.b, 1.0, UI.font.small)
    return w
end

-- ===========================================================================
-- FFSubTabs : ISPanel -- the segmented strip that switches between the views of
-- a single section (the design's Factions tab: Directory / Relations /
-- Leaderboard / Raid). One rounded outline around the whole strip, hairline
-- separators between segments, and the active segment carrying the accent plus
-- an underline. Width auto-sizes to the labels. onSelect(target, key).
-- ===========================================================================
FFSubTabs = ISPanel:derive("FFSubTabs")

function FFSubTabs:new(x, y, tabs, activeKey, target, onSelect)
    local font = UI.font.body
    local segs, total = {}, 0
    for _, t in ipairs(tabs) do
        -- labelKey routes through FF.text/getText -- the only path proven
        -- safe for accented PT-BR text (see LFS_Panel.lua's SECTIONS/drawRow
        -- for the same fix and why plain FF.tr(t.label) is not safe once a
        -- label actually contains an accent).
        local label = t.labelKey and FF.text(t.labelKey, t.label) or FF.tr(t.label)
        local w = UI.tw(font, label) + 28
        segs[#segs + 1] = { key = t.key, label = label, x = total, w = w }
        total = total + w
    end
    local o = ISPanel:new(x, y, total, UI.rowH(font))
    setmetatable(o, self); self.__index = self
    o.background = false
    o.font = font
    o.segs = segs
    o.activeKey = activeKey
    o.target = target
    o.onSelect = onSelect
    o.hoverIndex = nil
    return o
end

function FFSubTabs:prerender()
    local c = UI.color
    local w, h = self:getWidth(), self:getHeight()
    UI.roundFrame(self, 0, 0, w, h, 8, 1.0, c.border, c.bg)
    for i, s in ipairs(self.segs) do
        local active = (s.key == self.activeKey)
        if i > 1 then
            self:drawRect(s.x, 2, 1, h - 4, 1.0, c.border.r, c.border.g, c.border.b)
        end
        if active then
            UI.roundRect(self, s.x + 1, 1, s.w - 2, h - 2, 6, 0.14, c.accent)
            self:drawRect(s.x + 4, h - 3, s.w - 8, 2, 1.0, c.accent.r, c.accent.g, c.accent.b)
        elseif self.hoverIndex == i then
            UI.roundRect(self, s.x + 1, 1, s.w - 2, h - 2, 6, 0.6, c.panel2)
        end
        local col = active and c.accent or c.dim
        self:drawTextCentre(s.label, s.x + math.floor(s.w / 2),
            math.floor((h - UI.fh(self.font)) / 2) - 1, col.r, col.g, col.b, 1.0, self.font)
    end
end

function FFSubTabs:segAt(x)
    for i, s in ipairs(self.segs) do
        if x >= s.x and x < s.x + s.w then return i, s end
    end
end

function FFSubTabs:onMouseMove(dx, dy)
    self.hoverIndex = self:segAt(self:getMouseX())
end

function FFSubTabs:onMouseMoveOutside() self.hoverIndex = nil end

function FFSubTabs:onMouseUp(x, y)
    local _, seg = self:segAt(x)
    if seg and seg.key ~= self.activeKey and self.onSelect then
        getSoundManager():playUISound("UIActivateButton")
        self.onSelect(self.target, seg.key)
    end
    return true
end

function FFSubTabs:onMouseDown(x, y) return true end

-- ===========================================================================
-- setupScrollPane -- finish a scroll-children ISPanel: clip it, and make the mouse
-- wheel work. Call this on EVERY scroll pane, right after addScrollBars().
--
-- Clipping: setScrollChildren(true) only OFFSETS children by the scroll amount, it
-- never clips them, so without this a scrolled child at negative Y paints over whatever
-- sits above the panel. This is the vanilla idiom (ISScrollingListBox / ISModalEditRole):
-- stencil in prerender, clear in render -- render runs after the children, so the
-- stencil covers their draws.
--
-- The wheel: neither setScrollChildren nor addScrollBars installs a handler
-- (ISUIElement:addScrollBars only creates an ISScrollBar), and the inherited
-- ISUIElement:onMouseWheel returns false. A pane without this scrolls ONLY by dragging
-- the bar -- a failure mode seen in older, denser versions of this panel. It
-- used to be copy-pasted at each pane, so the two new panes simply never got it; folded
-- in here it cannot be forgotten. The name says "setup", not "clip", for the same
-- reason -- nobody skips a function that sounds like it does the whole job.
--
-- Lives here because both the main panel's tabs and the stall window need it.
-- ===========================================================================
function UI.setupScrollPane(scroll)
    scroll.prerender = function(s)
        s:setStencilRect(0, 0, s:getWidth(), s:getHeight())
        ISPanel.prerender(s)
    end
    scroll.render = function(s)
        ISPanel.render(s)
        s:clearStencilRect()
    end
    scroll.onMouseWheel = function(s, del)
        s:setYScroll(s:getYScroll() - del * 40)
        return true
    end
    if scroll.vscroll then scroll.vscroll.doRepaintStencil = true end
end

-- ===========================================================================
-- captureScroll -- read a scroll-children pane's offset before it gets thrown
-- away by a rebuild (clearChildren + a brand-new ISPanel), and hand back a
-- closure that reapplies it to the replacement pane.
--
-- Every rebuild in this mod (the stall window on a 1s timer, every Panel.lua
-- tab on a registry sync) tears down and recreates its scroll pane from
-- scratch rather than updating it in place, which is the right call for
-- correctness (see the "full teardown/rebuild" comment in Stalls.lua) but
-- silently drops YScroll back to 0 every time, since nothing else reads the
-- old pane before it is discarded. That reads as "scrolling doesn't work" --
-- worse, on the stall window's 1s timer, as "scrolling snaps back to the top"
-- mid-drag. Call captureScroll before clearChildren/creating the new pane,
-- then call the returned restorer AFTER the new pane's content is built and
-- setScrollHeight has run, so PZ's own clamping applies against the real
-- (new) content height rather than a zero-height pane.
-- ===========================================================================
function UI.captureScroll(oldScroll)
    local y = (oldScroll and oldScroll.getYScroll) and oldScroll:getYScroll() or nil
    return function(newScroll)
        if y and newScroll and newScroll.setYScroll then newScroll:setYScroll(y) end
    end
end

-- ===========================================================================
-- passWheel -- let a widget decline the mouse wheel so its scrolling parent gets it.
--
-- PZ dispatches the wheel top-down: UIElement.onMouseWheel walks its children in
-- reverse z-order and stops at the first one under the cursor that returns true,
-- skipping its OWN handler. ISTextEntryBox returns true unconditionally -- even on a
-- single-line box, where setYScroll clamps to 0 and nothing visibly moves -- so hovering
-- one silently eats the event and the pane behind it stops scrolling. Every entry box in
-- this mod is single-line and has nothing of its own to scroll, so declining is always
-- correct. Vanilla hits the same wall and solves it with ISRichTextPanel.blockMouseWheel;
-- ISTextEntryBox has no equivalent flag, hence the per-instance override.
-- ===========================================================================
function UI.passWheel(el)
    el.onMouseWheel = function() return false end
    return el
end

-- ===========================================================================
-- styleNavList -- (legacy) install a themed doDrawItem on an ISScrollingListBox.
-- The custom window draws its own sidebar now; kept for any other list use.
-- ===========================================================================
function UI.styleNavList(list)
    list.drawBorder = false
    list.doDrawItem = function(self, y, item, alt)
        local h = self.itemheight
        local w = self:getWidth()
        local selected = (self.selected == item.index)
        local hover = (self.mouseoverselected == item.index) and self:isMouseOver()
        local c = UI.color
        if selected then
            self:drawRect(0, y, w, h, 0.14, c.accent.r, c.accent.g, c.accent.b)
            self:drawRect(0, y, 3, h, 1.0, c.accent.r, c.accent.g, c.accent.b)
        elseif hover then
            self:drawRect(0, y, w, h, 1.0, c.panel2.r, c.panel2.g, c.panel2.b)
        end
        local sec = item.item
        local iconCol = selected and c.accent or c.dim
        UI.drawIcon(self, sec.icon, 12, y + math.floor((h - 18) / 2), 18, iconCol)
        local textCol = selected and c.accent or c.text
        self:drawText(sec.label, 40, y + math.floor((h - UI.fh(self.font)) / 2),
            textCol.r, textCol.g, textCol.b, 1.0, self.font)
        return y + h
    end
end

-- ===========================================================================
-- Danger dimming: multiplies every draw call's alpha across the whole panel
-- (main window + every FF* child widget below) so a zombie getting close
-- fades the interface and lets the player see/react to the game behind it --
-- see LFS_Panel.lua's updateDangerAlpha(), which is the only writer of
-- UI.dimAlpha (once per frame, in the main panel's own prerender). Everything
-- else here only reads it.
--
-- The panel's content is real child ISPanel/ISButton widgets (StatRow, FFCard,
-- FFButton, ClaimAreaList rows, ...), not one surface painted entirely by the
-- top window like LasciviousShop_Window.lua -- so a single override on the
-- main panel class alone would only dim its own header/sidebar chrome and
-- leave every card/row/button at full brightness. Same fix HardcoreKits_Theme.lua
-- already uses for its own tab widgets: install the multiplier on the leaf
-- draw primitives themselves (drawRect/drawText/drawTextCentre/drawTextRight/
-- drawTextureScaled/drawRectBorder), once per class, so it applies no matter
-- which widget instance -- or which UI.* helper -- ends up calling them.
--
-- Exemption: set `el.ffNoDim = true` on a specific instance (e.g. the close
-- button) to keep it fully legible regardless of dimAlpha -- checked per
-- draw call, not a global switch, so it never leaks onto anything else.
UI.dimAlpha = 1.0

local function dimmedAlpha(el, a)
    a = a or 1
    if el and el.ffNoDim then return a end
    return a * UI.dimAlpha
end
UI.dimmedAlpha = dimmedAlpha

-- Wraps `class`'s own drawRect/drawText/drawTextCentre/drawTextRight/
-- drawTextureScaled/drawRectBorder so every alpha argument passes through
-- dimmedAlpha() first. Safe to call on any ISPanel/ISButton-derived class
-- table, instantiated or not, since Lua's __index chain already resolves
-- `class.drawRect` etc. to the correct inherited implementation at call time
-- -- this just captures that as the fallback and shadows it for this class
-- (and therefore every instance of it) specifically.
function UI.installDimming(class)
    local baseDrawRect = class.drawRect
    local baseDrawRectBorder = class.drawRectBorder
    local baseDrawText = class.drawText
    local baseDrawTextCentre = class.drawTextCentre
    local baseDrawTextRight = class.drawTextRight
    local baseDrawTextureScaled = class.drawTextureScaled

    function class:drawRect(x, y, w, h, a, r, g, b)
        baseDrawRect(self, x, y, w, h, dimmedAlpha(self, a), r, g, b)
    end
    function class:drawRectBorder(x, y, w, h, a, r, g, b)
        baseDrawRectBorder(self, x, y, w, h, dimmedAlpha(self, a), r, g, b)
    end
    function class:drawText(str, x, y, r, g, b, a, font)
        baseDrawText(self, str, x, y, r, g, b, dimmedAlpha(self, a), font)
    end
    function class:drawTextCentre(str, x, y, r, g, b, a, font)
        baseDrawTextCentre(self, str, x, y, r, g, b, dimmedAlpha(self, a), font)
    end
    function class:drawTextRight(str, x, y, r, g, b, a, font)
        baseDrawTextRight(self, str, x, y, r, g, b, dimmedAlpha(self, a), font)
    end
    function class:drawTextureScaled(texture, x, y, w, h, a, r, g, b)
        baseDrawTextureScaled(self, texture, x, y, w, h, dimmedAlpha(self, a), r, g, b)
    end
end

-- The shared widget vocabulary every tab is built from (see the file header).
-- LasciviousFactionsSystemPanel itself and the smaller local classes that
-- live directly in LFS_Panel.lua (StatRow, Notice, ClaimAreaList, ...) install
-- the same dimming from that file, once each class exists.
UI.installDimming(FFButton)
UI.installDimming(FFCard)
UI.installDimming(FFBar)
UI.installDimming(FFBadge)
UI.installDimming(FFToggle)
UI.installDimming(FFStat)
UI.installDimming(FFRow)
UI.installDimming(FFRowGroup)
UI.installDimming(FFSubTabs)
