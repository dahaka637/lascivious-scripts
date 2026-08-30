if isServer() then return end

require "ISUI/ISEquippedItem"
require "ISUI/ISButton"
require "LasciviousShop_Shared"
require "LasciviousShop_Window"

local LS = LasciviousShop
local GAP = 15

-- Only vanilla buttons participate in our anchor calculation. This is important:
-- mods such as LFS dynamically pin their own button below the lowest sibling. If
-- two mod buttons both chase one another every frame, their Y positions grow
-- forever. Anchoring only to the known vanilla stack composes safely regardless
-- of mod load order; dynamic buttons can then place themselves below ours.
local VANILLA_INTERNAL = {
    INVENTORY=true, HEALTH=true, CRAFTING=true, BUILD=true, MOVABLE=true,
    SEARCH=true, ZONE=true, MAP=true, DEBUG=true, ARF=true, SAFETY=true,
    USERPANEL=true, ADMINPANEL=true, WARMANAGERPANEL=true,
}

local function vanillaGeometry(panel)
    local width, height, bottom = 48, 36, 0
    for _, child in pairs(panel:getChildren() or {}) do
        if child and VANILLA_INTERNAL[child.internal] then
            width = math.max(width, child:getWidth())
            height = math.max(height, child:getHeight())
            if child:isVisible() then bottom = math.max(bottom, child:getBottom()) end
        end
    end
    return width, height, bottom
end

local function maxVisibleButtonBottom(panel)
    local bottom = 0
    for _, child in pairs(panel:getChildren() or {}) do
        if child and child.Type == "ISButton" and child:isVisible() then
            bottom = math.max(bottom, child:getBottom())
        end
    end
    return bottom
end

local function clickShop()
    LasciviousShopWindow.toggle()
end

local function attach(panel)
    if not panel or panel.lasciviousShopBtn then return end
    if panel.chr and panel.chr.getPlayerNum and panel.chr:getPlayerNum() ~= 0 then return end
    local width, height, bottom = vanillaGeometry(panel)
    local maxY = math.max(0, getCore():getScreenHeight() - height - 4)
    local y = math.max(0, math.min(bottom + GAP, maxY))
    local button = ISButton:new(0, y, width, height, "", nil, clickShop)
    button.internal = "LASCIVIOUSSHOP"
    button:initialise()
    button:instantiate()
    button:setImage(getTexture("media/ui/LasciviousShop/sidebar-shop-button.png"))
    button:setDisplayBackground(false)
    button:ignoreWidthChange()
    button:ignoreHeightChange()
    panel:addChild(button)
    panel.lasciviousShopBtn = button
    if panel.addMouseOverToolTipItem then
        panel:addMouseOverToolTipItem(button, LS.text("SidebarTooltip", "Abrir Loja de Créditos (/shop)"))
    end
    panel:setHeight(math.max(panel:getHeight(), button:getBottom()))
end

local function updateGeometry(panel)
    local button = panel.lasciviousShopBtn
    if not button then return end
    local width, height, bottom = vanillaGeometry(panel)
    local maxY = math.max(0, getCore():getScreenHeight() - height - 4)
    button:setWidth(width)
    button:setHeight(height)
    button:setY(math.max(0, math.min(bottom + GAP, maxY)))
    panel:setHeight(math.max(button:getBottom(), maxVisibleButtonBottom(panel)))
end

if not ISEquippedItem.__lasciviousShopSidebarPatched then
    ISEquippedItem.__lasciviousShopSidebarPatched = true
    ISEquippedItem.__lasciviousShopOriginalInitialise = ISEquippedItem.initialise
    function ISEquippedItem:initialise()
        ISEquippedItem.__lasciviousShopOriginalInitialise(self)
        local ok, err = pcall(attach, self)
        if not ok then LS.log("WARNING: sidebar attach failed: " .. tostring(err)) end
    end

    ISEquippedItem.__lasciviousShopOriginalPrerender = ISEquippedItem.prerender
    function ISEquippedItem:prerender()
        ISEquippedItem.__lasciviousShopOriginalPrerender(self)
        pcall(updateGeometry, self)
    end
end

-- File-load patching catches future panels; this catches a bar already created by
-- UI bootstrap before mod Lua finished loading.
local function attachExistingPanel()
    local panel = ISEquippedItem.instance
    if panel and not panel.lasciviousShopBtn then
        local ok, err = pcall(attach, panel)
        if not ok then LS.log("WARNING: late sidebar attach failed: " .. tostring(err)) end
    end
end

-- Lua files can be reloaded by debug tooling. Replacing our previous callback
-- avoids accumulating identical OnGameStart listeners across those reloads.
if ISEquippedItem.__lasciviousShopOnGameStart and Events.OnGameStart.Remove then
    Events.OnGameStart.Remove(ISEquippedItem.__lasciviousShopOnGameStart)
end
ISEquippedItem.__lasciviousShopOnGameStart = attachExistingPanel
Events.OnGameStart.Add(attachExistingPanel)
