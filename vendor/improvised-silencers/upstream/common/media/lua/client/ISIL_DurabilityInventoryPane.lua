require "ISUI/ISInventoryPane"
require "ISIL_SilencerStats"

-- Inventory UI mods can replace ISInventoryPane or switch between multiple
-- concrete pane classes at runtime. Keep the hook state globally so reloading
-- this file cannot wrap one of our own wrappers, and track each class table
-- separately so a UI-class switch cannot create a recursive method chain.
local HOOK_VERSION = 2
local hookState = rawget(_G, "ISILInventoryPaneHookState")
if type(hookState) ~= "table" or hookState.version ~= HOOK_VERSION then
    hookState = {
        version = HOOK_VERSION,
        patchedClasses = {},
        discoveryTicksRemaining = 0,
        discoveryTickRegistered = false,
        lifecycleEventsRegistered = false,
    }
    _G.ISILInventoryPaneHookState = hookState
end

local function getSuppressorDurability(item)
    if not item or not instanceof(item, "HandWeapon") then
        return nil, nil, nil
    end

    local suppressor = item:getWeaponPart("Canon")
    if not ISILSilencerStats.isDurabilityTracked(suppressor) then
        return nil, nil, nil
    end

    local remaining, maximum = ISILSilencerDurability.peek(suppressor)
    return suppressor, remaining, maximum
end

local function getDurabilityBarColor(fraction)
    if fraction > 0.50 then
        local hc = getCore():getGoodHighlitedColor()
        return { r = hc:getR(), g = hc:getG(), b = hc:getB(), a = 1 }
    end
    if fraction > 0.25 then
        return { r = 0.95, g = 0.75, b = 0.10, a = 1 }
    end
    return { r = 0.90, g = 0.15, b = 0.10, a = 1 }
end

local function drawSuppressorDurability(self, item, y, xoff, yoff)
    local suppressor, remaining, maximum = getSuppressorDurability(item)
    if not suppressor or not remaining or not maximum or maximum <= 0 then
        return
    end

    local top = self.headerHgt + y * self.itemHgt + yoff
    local conditionText = getText("IGUI_invpanel_Condition") .. ":"
    local conditionTextWidth = getTextManager():MeasureStringX(self.font, conditionText)
    local weaponBarX = 40 + math.max(120, 30 + conditionTextWidth + 20) + xoff
    local weaponBarRight = weaponBarX + self:getProgressBarWidth()
    local iconSize = math.min(22, self.itemHgt - 2)
    local iconX = weaponBarRight + 10
    local iconY = top + (self.itemHgt - iconSize) / 2

    ISInventoryItem.renderItemIcon(self, suppressor, iconX, iconY,
        1.0, iconSize, iconSize)

    local barX = iconX + iconSize + 8
    local scrollWidth = self.vscroll and self.vscroll:getWidth() or 0
    local availableWidth = self.width - scrollWidth - barX - 8
    local barWidth = math.min(100, availableWidth)

    local indicatorWidth = iconSize
    if barWidth >= 24 then
        indicatorWidth = iconSize + 8 + barWidth
    end
    self.ISILSuppressorIndicatorRects = self.ISILSuppressorIndicatorRects or {}
    table.insert(self.ISILSuppressorIndicatorRects, {
        x = iconX,
        y = top,
        width = indicatorWidth,
        height = self.itemHgt,
    })

    if barWidth < 24 then
        return
    end

    local fraction = math.max(0, math.min(1, remaining / maximum))
    local fgBar = getDurabilityBarColor(fraction)
    self:drawProgressBar(barX, top + (self.itemHgt / 2) - 1,
        barWidth, self:getProgressBarHeight(), fraction, fgBar)
end

local function patchInventoryPaneClass(paneClass)
    if type(paneClass) ~= "table" then
        return false
    end

    if hookState.patchedClasses[paneClass]
        or rawget(paneClass, "ISILInventoryPaneHookVersion") == HOOK_VERSION then
        hookState.patchedClasses[paneClass] = true
        return false
    end

    local originalDrawItemDetails = paneClass.drawItemDetails
    local originalPrerender = paneClass.prerender
    local originalOnMouseMove = paneClass.onMouseMove
    if type(originalDrawItemDetails) ~= "function"
        or type(originalPrerender) ~= "function"
        or type(originalOnMouseMove) ~= "function" then
        return false
    end

    -- Mark the concrete class before replacing methods. If another load of this
    -- file occurs during UI initialization it will see the marker and leave the
    -- already captured originals alone.
    hookState.patchedClasses[paneClass] = true
    paneClass.ISILInventoryPaneHookVersion = HOOK_VERSION

    paneClass.prerender = function(self, ...)
        -- Rebuild the non-interactive indicator hit areas every frame so
        -- scrolling, resizing and sorting cannot leave stale coordinates.
        self.ISILSuppressorIndicatorRects = {}
        return originalPrerender(self, ...)
    end

    paneClass.onMouseMove = function(self, dx, dy)
        local result = originalOnMouseMove(self, dx, dy)
        local mouseX = self:getMouseX()
        local mouseY = self:getMouseY()

        for _, rect in ipairs(self.ISILSuppressorIndicatorRects or {}) do
            if mouseX >= rect.x and mouseX < rect.x + rect.width
                and mouseY >= rect.y and mouseY < rect.y + rect.height then
                -- Vanilla puts its quick drop button in the category column.
                -- Our suppressor indicator shares that space but is display-only.
                self:hideButtons()
                self.buttonOption = 0
                break
            end
        end

        return result
    end

    paneClass.drawItemDetails = function(self, item, y, xoff, yoff, red)
        local result = originalDrawItemDetails(self, item, y, xoff, yoff, red)
        drawSuppressorDurability(self, item, y, xoff, yoff)
        return result
    end

    return true
end

local function discoverInventoryPaneClasses()
    -- Always patch the active class. CleanUI exposes both of its concrete
    -- classes through optional globals; rawget keeps this file independent of
    -- CleanUI and safe when no UI mod is installed.
    patchInventoryPaneClass(rawget(_G, "ISInventoryPane"))
    patchInventoryPaneClass(rawget(_G, "CleanUI_Clean_ISInventoryPane"))
    patchInventoryPaneClass(rawget(_G, "CleanUI_Vanilla_ISInventoryPane"))
end

local function discoveryTick()
    discoverInventoryPaneClasses()
    hookState.discoveryTicksRemaining = hookState.discoveryTicksRemaining - 1
    if hookState.discoveryTicksRemaining <= 0 then
        Events.OnTick.Remove(discoveryTick)
        hookState.discoveryTickRegistered = false
    end
end

local function beginClassDiscovery()
    discoverInventoryPaneClasses()

    -- CleanUI creates its alternate class aliases during UI bootstrap. Watch a
    -- short startup window so both concrete classes are patched, then stop the
    -- tick callback. Later mode switches reuse those same class tables.
    hookState.discoveryTicksRemaining = math.max(hookState.discoveryTicksRemaining or 0, 180)
    if not hookState.discoveryTickRegistered and Events and Events.OnTick then
        hookState.discoveryTickRegistered = true
        Events.OnTick.Add(discoveryTick)
    end
end

beginClassDiscovery()

if not hookState.lifecycleEventsRegistered then
    hookState.lifecycleEventsRegistered = true
    if Events and Events.OnGameBoot then
        Events.OnGameBoot.Add(beginClassDiscovery)
    end
    if Events and Events.OnGameStart then
        Events.OnGameStart.Add(beginClassDiscovery)
    end
end
