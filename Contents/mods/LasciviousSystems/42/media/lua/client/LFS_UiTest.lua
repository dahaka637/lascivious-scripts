-- Lascivious Factions System - panel layout self-test (client side, admin only).
--
-- Why this exists: every tab lays itself out with hand-computed pixel arithmetic
-- against a live, resizable content pane, and a mistake there is invisible until
-- someone happens to open that tab at that window size. The 1.2.7 Claims tab
-- shipped with its whole bottom control row overlapping for exactly that reason.
--
-- `/ff admin uitest` drives the real panel through every tab at several window
-- widths and reports two things that are always bugs:
--   * two CONTROLS overlapping   -- one of them is unclickable
--   * a child escaping its parent -- it is drawn clipped or off the card
-- Decorative widgets (cards, bars, labels, notices) are deliberately not checked
-- against each other: they legitimately sit behind and under other things.
--
-- It runs the whole sweep twice: once at the real font, once with UI.fhScale raised
-- so every font-derived measurement grows as it would on a 4K screen (see 1.2.10).
-- Anything left hardcoded stays put while its siblings grow, so it spills out of its
-- parent and the escapes-y check catches it.
--
-- This is a layout check, not a rendering check. It cannot see a colour mistake or
-- text that is merely ugly -- only geometry that is provably wrong. Three specific
-- blind spots worth knowing before you trust a clean run:
--   * Text drawn inside a widget's own prerender (FFCard titles, StatRow, list rows,
--     the window header) has no child rect, so a collision with it is invisible here.
--     Walking the tabs with the game's Font Size set to 38px is the only check that
--     sees those.
--   * Vanilla widgets (ISLabel, ISTextEntryBox, ISButton, ISComboBox) render at the
--     real font whatever UI.fhScale says, so the scaled pass does not test whether
--     their own text still fits them.
--   * Scroll panes legitimately suppress escapes-y -- that is what the scrollbar is
--     for -- so only card-level overflow inside them is caught.

require "LFS_Shared"
require "LFS_UI"   -- UI.fh / UI.fhScale are bound at load below

local FF = LasciviousFactionsSystem
local UI = FF.UI

-- Second sweep pretends every font is this much taller. ~2.5x is the real jump from
-- PZ's 16px atlas to the 38px one any screen 1872px tall or more resolves to.
local FONT_SCALE_PASS = 2.5

-- Widgets where an overlap is unambiguously a defect.
local CONTROL_TYPES = {
    FFButton = true, ISButton = true, ISTextEntryBox = true, ISComboBox = true,
    ISTickBox = true, FFToggle = true, FFRolePermRow = true, FFColorSwatch = true,
    ISScrollingListBox = true, FFSubTabs = true,
}

-- Scroll bars are added by addScrollBars() and sit on top of the pane's own edge
-- by design; walking into them only produces noise.
local SKIP_TYPES = { ISScrollBar = true }

-- Every distinct view the panel can show. `sub` selects a Factions sub-tab;
-- `roles` opens the Members roles side pane (a different layout, not just a flag).
local VIEWS = {
    { key = "overview" },
    { key = "members" },
    { key = "members",  roles = true,          label = "members+roles" },
    { key = "claims" },
    { key = "factions", sub = "directory" },
    { key = "factions", sub = "relations" },
    { key = "factions", sub = "leaderboard" },
    { key = "factions", sub = "raid" },
    { key = "settings" },
    { key = "help" },
}

local DEFAULT_WIDTHS = { 620, 760, 1000 }

-- At or below this many children, a section built its empty state rather than its real
-- one. Every stub path in the panel is a single addLabel or a lone Notice, and the
-- cheapest real layout (Help) is well clear of it.
local STUB_CHILDREN = 2

local function say(text)
    print("[LFS] " .. text)
end

-- A short, human-findable name for a widget: its label if it has one, else its
-- type. This is what tells you WHICH button is misplaced.
local function describe(el)
    local name = el.title or el.text or el.label
    if type(name) ~= "string" or name == "" then name = el.Type or "?" end
    if #name > 24 then name = string.sub(name, 1, 21) .. "..." end
    return string.format("%s[%d,%d %dx%d]", name, el:getX(), el:getY(), el:getWidth(), el:getHeight())
end

local function overlaps(a, b)
    -- 1px of slack: adjacent widgets sharing a border are not a collision.
    local ax, ay, aw, ah = a:getX(), a:getY(), a:getWidth(), a:getHeight()
    local bx, by, bw, bh = b:getX(), b:getY(), b:getWidth(), b:getHeight()
    return (ax + aw - 1 > bx) and (bx + bw - 1 > ax)
       and (ay + ah - 1 > by) and (by + bh - 1 > ay)
end

local function visibleChildren(el)
    local out = {}
    local kids = el.getChildrenInOrder and el:getChildrenInOrder()
    if not kids then return out end
    for _, c in ipairs(kids) do
        local ok = c and c.getX and not SKIP_TYPES[c.Type or ""]
        if ok then
            -- isVisible() instantiates a bare element; every child here is already
            -- added (hence instantiated), but stay defensive -- this runs over a
            -- live UI tree and must never be the thing that throws.
            local shown = true
            pcall(function() shown = c:isVisible() end)
            if shown then out[#out + 1] = c end
        end
    end
    return out
end

-- Recursive geometry check of one container. `report(kind, detail)` collects.
local function checkContainer(el, path, report, depth)
    if depth > 6 then return end
    local kids = visibleChildren(el)
    local pw, ph = el:getWidth(), el:getHeight()
    -- A scrolling pane's children are expected to run past its bottom edge; that
    -- is what the scrollbar is for. Horizontal fit still matters. The flag lives on
    -- the java object (setScrollChildren), not the Lua table -- reading a Lua field
    -- here would silently report every scroll pane's contents as escaping.
    local scrolls = false
    pcall(function() scrolls = el:getScrollChildren() == true end)

    -- A titled FFCard draws its title itself, so a child placed above contentTop()
    -- collides with painted text no rect walker can see. This one explicit assertion
    -- covers the single most common form of that -- and is exactly the bug that
    -- broke every card on every tab at 4K before 1.2.10.
    local cardTop = nil
    if el.Type == "FFCard" and el.title and el.contentTop then
        pcall(function() cardTop = el:contentTop() end)
    end

    for i, c in ipairs(kids) do
        local cx, cy, cw, ch = c:getX(), c:getY(), c:getWidth(), c:getHeight()
        if cx < -1 or cx + cw > pw + 1 then
            report("escapes-x", string.format("%s > %s  (parent width %d)", path, describe(c), pw))
        end
        if cardTop and cy < cardTop then
            report("under-title", string.format("%s > %s  (card content starts at %d)", path, describe(c), cardTop))
        end
        if not scrolls and cy + ch > ph + 1 then
            report("escapes-y", string.format("%s > %s  (parent height %d)", path, describe(c), ph))
        end
        if CONTROL_TYPES[c.Type or ""] then
            for j = i + 1, #kids do
                local d = kids[j]
                if CONTROL_TYPES[d.Type or ""] and overlaps(c, d) then
                    report("overlap", string.format("%s > %s  OVER  %s", path, describe(c), describe(d)))
                end
            end
        end
        checkContainer(c, path .. " > " .. (c.Type or "?"), report, depth + 1)
    end
end

-- ---------------------------------------------------------------------------
-- /ff admin uitest [width ...]
-- ---------------------------------------------------------------------------
function FF.uiTest(widths)
    local panel = _G.LasciviousFactionsSystemPanel and LasciviousFactionsSystemPanel.instance
    if not panel or not panel.content then
        say("uitest: open the faction panel first (/ff panel), then re-run.")
        return
    end
    if panel.collapsed then
        say("uitest: the panel is minimized -- restore it first.")
        return
    end
    if not (FF.getFactionOfPlayer and select(2, FF.getFactionOfPlayer(getPlayer():getUsername()))) then
        say("uitest: NOTE -- you are not in a faction, so most tabs render only their")
        say("uitest:         empty state. Join or /ff admin create one for real coverage.")
    end

    widths = (widths and #widths > 0) and widths or DEFAULT_WIDTHS

    -- Restore everything afterwards: this drives the player's real, open window.
    local savedW, savedH = panel:getWidth(), panel:getHeight()
    local savedSection = panel.activeSection
    local savedSub, savedRoles = panel.factionsSubTab, panel.showRoles

    local findings, checked = 0, 0
    local stubs = {}   -- [label] = true for views that rendered only their empty state
    local screenW = getCore():getScreenWidth()

    -- What the layout is actually being computed against. Print it: the pads in
    -- UI.lineH / UI.rowH / UI.cardTop were reverse-engineered from the pre-1.2.10
    -- literals assuming fh(Small)=18 and fh(NewSmall)=14, so if this line disagrees
    -- the pads want retuning against these numbers rather than against a guess.
    say(string.format("uitest: font heights -- title %d, body %d, small %d, big %d",
        UI.fh(UI.font.title), UI.fh(UI.font.body), UI.fh(UI.font.small), UI.fh(UI.font.big)))

    local function sweep(scale)
        UI.fhScale = scale
        for _, w in ipairs(widths) do
            local useW = math.min(w, screenW)
            panel:onResized(useW, savedH)
            for _, view in ipairs(VIEWS) do
                local sub = view.sub
                local label = view.label or (sub and (view.key .. "/" .. sub)) or view.key
                local where = string.format("%dpx %s%s", useW, label,
                    (scale ~= 1) and string.format(" @%.1fx font", scale) or "")
                panel.showRoles = view.roles and true or false
                if view.sub then panel.factionsSubTab = view.sub end

                -- showSection catches builder errors itself now (so a player gets a
                -- visible failure notice instead of a half-drawn tab), which means the
                -- pcall here can no longer see them. It records the error on the panel
                -- instead; both are checked, so this keeps working either way.
                local built = pcall(function() panel:showSection(view.key) end)
                local builderErr = panel.sectionError
                if not built or builderErr then
                    findings = findings + 1
                    say(string.format("uitest: BUILD ERROR  %s -- %s", where,
                        builderErr and tostring(builderErr) or "showSection threw"))
                else
                    checked = checked + 1
                    -- A view that produced almost nothing rendered its EMPTY state and
                    -- was never really exercised -- "you're not in a faction", "no
                    -- factions have a claim to raid". Counting those separately is the
                    -- whole point: a factionless sweep used to report a clean bill of
                    -- health for tabs it had not touched, which is how a crashing Raid
                    -- tab passed this tool for four releases.
                    local kids = 0
                    pcall(function() kids = #panel.content:getChildrenInOrder() end)
                    if kids <= STUB_CHILDREN then
                        stubs[label] = true
                    end
                    checkContainer(panel.content, where, function(kind, detail)
                        findings = findings + 1
                        say(string.format("uitest: %-9s %s", kind, detail))
                    end, 0)
                end
            end
        end
    end

    -- Pass 1 at the real font. Pass 2 pretends the font is FONT_SCALE_PASS times
    -- taller, which is roughly the jump from the 16px atlas to the 38px one a 4K
    -- screen gets. Anything whose height is still a hardcoded literal will not grow
    -- while its font-derived siblings do, so its children spill out of it and the
    -- escapes-y check above fires. That makes the high-DPI bug class reproducible on
    -- an ordinary 1080p dev machine -- see this file's header for what it cannot see.
    -- pcall so a throwing tab can never leave the player's panel stuck at 2.5x.
    local ok, err = pcall(function()
        sweep(1)
        sweep(FONT_SCALE_PASS)
    end)
    UI.fhScale = 1
    if not ok then
        findings = findings + 1
        say("uitest: ABORTED -- " .. tostring(err))
    end

    panel.factionsSubTab, panel.showRoles = savedSub, savedRoles
    panel:onResized(savedW, savedH)
    if savedSection then pcall(function() panel:showSection(savedSection) end) end

    local summary = string.format("uitest: %d views checked at %d width(s) -- %d finding(s).",
        checked, #widths, findings)
    say(summary)
    if findings == 0 then say("uitest: no overlapping controls and nothing escaping its parent.") end

    -- Which views were never really exercised. Reported AFTER the findings count so a
    -- "0 findings" line is never the last word: a clean run over empty states proves
    -- nothing, and reading it as coverage is exactly the mistake that let the Raid tab
    -- ship broken.
    local stubList = {}
    for label in pairs(stubs) do stubList[#stubList + 1] = label end
    table.sort(stubList)
    if #stubList > 0 then
        say(string.format("uitest: %d view(s) rendered ONLY their empty state: %s",
            #stubList, table.concat(stubList, ", ")))
        say("uitest:   those were not really tested -- re-run in a faction (and with a")
        say("uitest:   claim and a raid) to cover their real layouts.")
    end
    local p = getPlayer()
    if p then p:setHaloNote(summary, 255, 255, 255, 300) end
end

print("[LFS] uitest lua loaded")
