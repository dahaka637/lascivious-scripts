-- Current-territory HUD: transparent text in the owning faction's colour.

require "ISUI/ISPanel"
require "LFS_Shared"
require "LFS_Claims"
require "LFS_UI"

local FF = LasciviousFactionsSystem
local Claims = FF.Claims
local UI = FF.UI

if FF.TerritoryOverlay then return end

local TerritoryOverlay = ISPanel:derive("LFSTerritoryOverlay")
FF.TerritoryOverlay = TerritoryOverlay
local clampPosition

function TerritoryOverlay:new()
    local width = 420
    local o = ISPanel:new(math.floor((getCore():getScreenWidth() - width) / 2), 72,
        width, UI.fh(UI.font.title) + 12)
    setmetatable(o, self)
    self.__index = self
    o.background = false
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.factionName = nil
    o.dragging = false
    return o
end

function TerritoryOverlay:prerender()
    local name = self.factionName
    if not name then return end

    local text = FF.text("UI_LFS_CurrentTerritory", "%s territory", name)
    local desiredWidth = math.max(120, UI.tw(UI.font.title, text) + 24)
    if self:getWidth() ~= desiredWidth then
        local centreX = self:getX() + self:getWidth() / 2
        self:setWidth(desiredWidth)
        local x, y = clampPosition(self, centreX - desiredWidth / 2, self:getY())
        self:setX(x)
        self:setY(y)
    end
    local color = UI.factionColor(name)
    local centre = math.floor(self:getWidth() / 2)
    -- Subtle shadow for legibility; there is intentionally no filled background.
    self:drawTextCentre(text, centre + 1, 3, 0, 0, 0, 0.85, UI.font.title)
    self:drawTextCentre(text, centre, 2, color.r, color.g, color.b, 1.0, UI.font.title)
end

clampPosition = function(self, x, y)
    local maxX = math.max(0, getCore():getScreenWidth() - self:getWidth())
    local maxY = math.max(0, getCore():getScreenHeight() - self:getHeight())
    return math.max(0, math.min(maxX, x)), math.max(0, math.min(maxY, y))
end

local function savePosition(self)
    local player = getPlayer()
    if not player then return end
    local md = player:getModData()
    md.LFS_territoryOverlayX = math.floor(self:getX())
    md.LFS_territoryOverlayY = math.floor(self:getY())
end

function TerritoryOverlay:onMouseDown(x, y)
    if not self.factionName then return false end
    self.dragging = true
    self:setCapture(true)
    self:bringToTop()
    return true
end

function TerritoryOverlay:onMouseMove(dx, dy)
    if not self.dragging then return end
    local x, y = self:getX() + dx, self:getY() + dy
    x, y = clampPosition(self, x, y)
    self:setX(x)
    self:setY(y)
end

function TerritoryOverlay:onMouseUp(x, y)
    if not self.dragging then return false end
    self.dragging = false
    self:setCapture(false)
    savePosition(self)
    return true
end

function TerritoryOverlay:onMouseUpOutside(x, y)
    if self.dragging then
        self.dragging = false
        self:setCapture(false)
        savePosition(self)
    end
end

function TerritoryOverlay:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

local lastTileX, lastTileY, lastCheckAt
local function updateVisibility()
    local overlay = FF.territoryOverlay
    if not overlay then return end
    local player = getPlayer()
    local name
    if player and not player:isDead() then
        local x, y = math.floor(player:getX()), math.floor(player:getY())
        local now = getTimestamp()
        -- Movement is reflected immediately; while standing still, recheck once a
        -- second so a freshly projected/unclaimed zone is still noticed. This used
        -- to perform the PhunZones lookup and setVisible call every render tick.
        if x == lastTileX and y == lastTileY and now == lastCheckAt then return end
        lastTileX, lastTileY, lastCheckAt = x, y, now
        name = Claims.factionAt(x, y)
    else
        lastTileX, lastTileY, lastCheckAt = nil, nil, nil
    end
    if overlay.factionName == name then return end
    overlay.factionName = name
    overlay:setVisible(name ~= nil)
end

local function createOverlay()
    if FF.territoryOverlay then FF.territoryOverlay:removeFromUIManager() end
    local overlay = TerritoryOverlay:new()
    overlay:initialise()
    local player = getPlayer()
    local md = player and player:getModData()
    if md and tonumber(md.LFS_territoryOverlayX) and tonumber(md.LFS_territoryOverlayY) then
        local x, y = clampPosition(overlay,
            tonumber(md.LFS_territoryOverlayX), tonumber(md.LFS_territoryOverlayY))
        overlay:setX(x)
        overlay:setY(y)
    end
    overlay:addToUIManager()
    overlay:setAlwaysOnTop(true)
    overlay:setVisible(false)
    FF.territoryOverlay = overlay
end

if FF._territoryOverlayGameStartHook then
    Events.OnGameStart.Remove(FF._territoryOverlayGameStartHook)
end
if FF._territoryOverlayTickHook then Events.OnTick.Remove(FF._territoryOverlayTickHook) end
FF._territoryOverlayGameStartHook = createOverlay
FF._territoryOverlayTickHook = updateVisibility
Events.OnGameStart.Add(createOverlay)
Events.OnTick.Add(updateVisibility)
