-- Hide PhunZones' persistent location widget everywhere. It is the framed box
-- that shows a city/zone name near the minimap; LFS uses its own frameless,
-- movable label only while the player is inside faction territory.
-- PhunZones' temporary welcome marquee is suppressed only for LFS zones.

require "LFS_Shared"

local FF = LasciviousFactionsSystem
if isServer() then return end

FF._phunZonesUiFilterState = type(FF._phunZonesUiFilterState) == "table"
    and FF._phunZonesUiFilterState or {}
local filterState = FF._phunZonesUiFilterState
local installed = false

local function isFactionZone(zone)
    local key = zone and zone.key
    return type(key) == "string"
        and string.sub(key, 1, #FF.ZONE_PREFIX) == FF.ZONE_PREFIX
end

local function hideWidgetInstance(Widget, playerIndex)
    local panel = Widget.instances and Widget.instances[playerIndex]
    if not panel then return end
    panel.data = {}
    panel:setVisible(false)
end

local function closeWelcomeInstance(Welcome, playerIndex)
    local panel = Welcome.instances and Welcome.instances[playerIndex]
    if not panel then return end
    if panel.close then panel:close() else panel:setVisible(false) end
end

local function installFilter()
    local PZ = _G.PhunZones
    local Widget = PZ and PZ.ui and PZ.ui.widget
    local Welcome = PZ and PZ.ui and PZ.ui.welcome
    if not (Widget and Widget.OnOpenPanel and Widget.setData
            and Welcome and Welcome.OnOpenPanel) then
        return false
    end

    -- Already patched by a previous Lua load: reuse the existing wrappers instead
    -- of wrapping Welcome.OnOpenPanel again on every reload.
    if filterState.installed and filterState.widget == Widget
        and filterState.welcome == Welcome then
        installed = true
        for playerIndex = 0, 3 do hideWidgetInstance(Widget, playerIndex) end
        return true
    end

    -- Disable the framed location widget globally, including ordinary city zones.
    -- Do not call getEffectiveZone here: during OnGameStart PhunZones has already
    -- stored a zone name on the player but data.lookup may not exist yet, which is
    -- exactly what caused the startup Lua error reported in console.txt.
    Widget.OnOpenPanel = function(playerObj, playerIndex)
        playerIndex = playerIndex or (playerObj and playerObj:getPlayerNum()) or 0
        hideWidgetInstance(Widget, playerIndex)
        return nil
    end

    Widget.setData = function(self, data)
        self.data = {}
        self:setVisible(false)
    end

    local originalWelcomeOpen = Welcome.OnOpenPanel
    Welcome.OnOpenPanel = function(playerObj, zone)
        if isFactionZone(zone) then
            local playerIndex = playerObj and playerObj:getPlayerNum() or 0
            closeWelcomeInstance(Welcome, playerIndex)
            return nil
        end
        return originalWelcomeOpen(playerObj, zone)
    end

    installed = true
    filterState.installed = true
    filterState.widget = Widget
    filterState.welcome = Welcome
    -- PhunZones may have created its widget earlier in the same OnGameStart event.
    -- Apply the filter immediately as well as intercepting all future openings.
    for playerIndex = 0, 3 do
        hideWidgetInstance(Widget, playerIndex)
    end
    print("[LFS] PhunZones framed location widget disabled; faction welcome filter ready")
    return true
end

local function installWhenReady()
    if installFilter() then
        Events.OnTick.Remove(installWhenReady)
        if FF._phunZonesUiReadyTick == installWhenReady then FF._phunZonesUiReadyTick = nil end
    end
end

local function installPhunZonesUiAtGameStart()
    if FF._phunZonesUiReadyTick then Events.OnTick.Remove(FF._phunZonesUiReadyTick) end
    FF._phunZonesUiReadyTick = nil
    if not installFilter() then
        FF._phunZonesUiReadyTick = installWhenReady
        Events.OnTick.Add(installWhenReady)
    end
end
if FF._phunZonesUiGameStartHook then
    Events.OnGameStart.Remove(FF._phunZonesUiGameStartHook)
end
FF._phunZonesUiGameStartHook = installPhunZonesUiAtGameStart
Events.OnGameStart.Add(installPhunZonesUiAtGameStart)
