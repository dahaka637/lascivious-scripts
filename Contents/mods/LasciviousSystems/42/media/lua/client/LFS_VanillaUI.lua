-- Lascivious Factions System - vanilla UI takeover (client side).
--
-- Multiplayer's "Client" info panel (ISUserPanelUI) has a Factions button that
-- opens the VANILLA faction system (ISFactionUI / ISCreateFactionUI) -- a second,
-- overlapping factions system alongside this mod. Redirect that button to the
-- Lascivious Factions System dashboard instead, so players only ever see one system.
--
-- Class-level method overrides installed on OnGameStart (the same pattern as
-- LFS_MapOverlay's prerender hooks): guarded by __ffOrig* markers so
-- they install once, chain the originals for every other button, and degrade to a
-- no-op when ISUserPanelUI doesn't exist (singleplayer never builds the panel).

require "LFS_Shared"
require "LFS_Panel"

local FF = LasciviousFactionsSystem

if isServer() then return end

local function installHooks()
    if not (_G.ISUserPanelUI and ISUserPanelUI.onOptionMouseDown) then return end
    if ISUserPanelUI.__ffOrigMouseDown then return end

    -- The FACTIONPANEL button opens our dashboard; everything else chains through.
    ISUserPanelUI.__ffOrigMouseDown = ISUserPanelUI.onOptionMouseDown
    function ISUserPanelUI:onOptionMouseDown(button, x, y)
        if button and button.internal == "FACTIONPANEL" then
            LasciviousFactionsSystemPanel.toggle()
            return
        end
        return ISUserPanelUI.__ffOrigMouseDown(self, button, x, y)
    end

    -- Vanilla retitles the button to "Create Faction" and disables it below the
    -- FactionDaySurvivedToCreate gate; the framework has its own create flow, so
    -- keep the button titled "Factions" and always clickable.
    if ISUserPanelUI.updateButtons then
        ISUserPanelUI.__ffOrigUpdateButtons = ISUserPanelUI.updateButtons
        function ISUserPanelUI:updateButtons()
            ISUserPanelUI.__ffOrigUpdateButtons(self)
            if self.factionBtn then
                self.factionBtn.title = FF.tr("Factions")
                self.factionBtn.enable = true
                self.factionBtn.tooltip = nil
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Sidebar button
-- ---------------------------------------------------------------------------
-- B42's left icon column (inventory / health / crafting / build / map ...) is
-- ISEquippedItem, which builds every button by hand in :initialise() and
-- dispatches clicks through a closed if/elseif on button.internal. There is no
-- registration API for mods, so the only way in is a class-level patch: let
-- vanilla build its bar, then append our own button as a child.
--
-- :prerender is patched as well as :initialise because the bar is not static --
-- the debug/admin/war buttons appear and disappear at runtime, and changing the
-- sidebar-size option rebuilds the whole panel. Re-deriving our Y from the lowest
-- VISIBLE sibling every frame keeps us pinned to the bottom of the stack in all
-- of those cases, and resizing the panel keeps its hit-testing correct.

local SIDEBAR_GAP = 15

-- The button must stay fully on-screen: with a long icon stack (admin/debug buttons)
-- "below the lowest sibling" can pass the screen bottom, leaving a button that is
-- visible (children aren't clipped) but can never be clicked.
local function clampButtonY(y, h)
    local maxY = getCore():getScreenHeight() - h - 4
    if y > maxY then y = maxY end
    if y < 0 then y = 0 end
    return y
end

-- Append our button to an ISEquippedItem that has already built its own children.
local function attachSidebarButton(panel)
    if not panel or panel.ffFactionBtn then return end
    if FF.hudIconPosition() ~= 1 then return end
    -- Split screen builds one bar per local player; only the first gets it.
    if panel.chr and panel.chr.getPlayerNum and panel.chr:getPlayerNum() ~= 0 then return end

    -- Match whatever size vanilla is using, so we follow the sidebar-size option
    -- without having to read it ourselves.
    local w, h, bottom = 48, 36, 0
    for _, child in pairs(panel:getChildren()) do
        if child.Type == "ISButton" then
            w = math.max(w, child:getWidth())
            h = math.max(h, child:getHeight())
            bottom = math.max(bottom, child:getBottom())
        end
    end

    local btn = FF.HudIcon:new(0, clampButtonY(bottom + SIDEBAR_GAP, h), w, h)
    btn:initialise()
    btn:instantiate()
    btn:setDisplayBackground(false)
    btn:ignoreWidthChange()
    btn:ignoreHeightChange()
    panel:addChild(btn)
    panel.ffFactionBtn = btn
    if panel.addMouseOverToolTipItem then
        panel:addMouseOverToolTipItem(btn,
            FF.text("UI_LFS_SidebarTooltip", "Open faction panel (J)"))
    end

    -- Grow the parent to cover the button IMMEDIATELY. PZ hit-testing is
    -- hierarchical: a child below its parent's rect is drawn (children aren't
    -- clipped) but never receives clicks -- a visible-but-dead button. The
    -- prerender sync below keeps this correct afterwards, but must not be the
    -- only thing establishing it.
    if panel:getHeight() < btn:getBottom() then
        panel:setHeight(btn:getBottom())
    end
    FF.print(string.format("sidebar button attached at y=%d (%dx%d), bar height %d",
        btn:getY(), w, h, panel:getHeight()))
end

-- Remove a previously attached button (the effective position resolved to
-- something other than "left sidebar" once client ModOptions loaded).
local function detachSidebarButton(panel)
    if not (panel and panel.ffFactionBtn) then return end
    local btn = panel.ffFactionBtn
    panel.ffFactionBtn = nil
    pcall(function()
        for i = #(panel.mouseOverList or {}), 1, -1 do
            if panel.mouseOverList[i].object == btn then
                table.remove(panel.mouseOverList, i)
            end
        end
        btn:setVisible(false)
        panel:removeChild(btn)
        -- Release any dead transparent space that had existed solely for this icon.
        local bottom = 0
        for _, child in pairs(panel:getChildren() or {}) do
            if child and child.isButton and child:isVisible() then
                bottom = math.max(bottom, child:getBottom())
            end
        end
        panel:setHeight(bottom)
    end)
    FF.print("sidebar button removed (position preference is not 'left sidebar')")
end

local function installSidebarButton()
    if not (_G.ISEquippedItem and ISEquippedItem.initialise) then
        return FF.print("WARNING: no ISEquippedItem; faction sidebar button unavailable")
    end
    if ISEquippedItem.__ffOrigInitialise then return end

    ISEquippedItem.__ffOrigInitialise = ISEquippedItem.initialise
    function ISEquippedItem:initialise()
        ISEquippedItem.__ffOrigInitialise(self)
        local ok, err = pcall(function() attachSidebarButton(self) end)
        if not ok then
            FF.print("WARNING: faction sidebar button failed: " .. tostring(err))
        end
    end

    ISEquippedItem.__ffOrigPrerender = ISEquippedItem.prerender
    function ISEquippedItem:prerender()
        ISEquippedItem.__ffOrigPrerender(self)
        -- Re-evaluate the sandbox/client preference live. This also makes an admin
        -- change to ShowFactionSidebarButton take effect without reconstructing the
        -- entire vanilla sidebar.
        if FF.hudIconPosition() ~= 1 then
            detachSidebarButton(self)
            return
        elseif not self.ffFactionBtn then
            attachSidebarButton(self)
        end
        local btn = self.ffFactionBtn
        if not btn then return end
        pcall(function()
            local bottom = 0
            for _, child in pairs(self:getChildren()) do
                if child.Type == "ISButton" and child ~= btn and child:isVisible() then
                    bottom = math.max(bottom, child:getBottom())
                end
            end
            -- No visible sibling this frame (mid-rebuild): keep the button where it
            -- is rather than bailing -- the height sync below must STILL run, or the
            -- parent stays too short and the button goes click-dead.
            if bottom > 0 then
                btn:setY(clampButtonY(bottom + SIDEBAR_GAP, btn:getHeight()))
            end
            -- The parent's rect is the hit-test gate for our child; it must always
            -- reach the button's bottom edge (and shrink back when siblings hide,
            -- so the invisible bar doesn't block world clicks below the button).
            if self:getHeight() ~= btn:getBottom() then
                self:setHeight(btn:getBottom())
            end
        end)
    end
end

if FF._vanillaUiInstallHook then Events.OnGameStart.Remove(FF._vanillaUiInstallHook) end
FF._vanillaUiInstallHook = installHooks
Events.OnGameStart.Add(installHooks)

-- Installed at FILE LOAD, not on OnGameStart: ISEquippedItem is constructed by the
-- engine during UI bootstrap, which can already have happened by the time
-- OnGameStart fires -- patching then would miss the live panel entirely. The option
-- is therefore read inside the wrapper rather than here, since sandbox vars are not
-- guaranteed to be populated this early.
installSidebarButton()

-- Belt and braces + late re-evaluation. Two reasons to run at OnGameStart:
--   1. The bar may have been built before our initialise patch landed, so attach
--      directly to the live instance.
--   2. The attach gate reads FF.hudIconPosition(), whose per-client ModOptions
--      combo only loads at OnGameStart (Panel.lua) -- so the position resolved at
--      UI-bootstrap attach time can be wrong. Re-resolve now: remove the button if
--      the real preference isn't "left sidebar", attach it if it is and missing.
local function reconcileFactionSidebarButton()
    pcall(function()
        local panel = _G.ISEquippedItem and ISEquippedItem.instance
        if not panel then return end
        local pos = FF.hudIconPosition()
        FF.print("resolved faction button position: " .. tostring(pos)
            .. " (0=hidden 1=left sidebar 2=top-right)")
        if pos == 1 then
            attachSidebarButton(panel)
        else
            detachSidebarButton(panel)
        end
    end)
end
if FF._vanillaUiSidebarGameStartHook then
    Events.OnGameStart.Remove(FF._vanillaUiSidebarGameStartHook)
end
FF._vanillaUiSidebarGameStartHook = reconcileFactionSidebarButton
Events.OnGameStart.Add(reconcileFactionSidebarButton)
