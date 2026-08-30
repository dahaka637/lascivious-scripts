if isServer() then
    return
end

require "DebugUIs/DebugMenu/ISDebugMenu"
local Core = PhunZones

PhunZonesAdminHookRegistry = PhunZonesAdminHookRegistry or {}
local hookRegistry = PhunZonesAdminHookRegistry

local debugCanWrap = true
if hookRegistry.debugWrapper then
    if ISDebugMenu.setupButtons == hookRegistry.debugWrapper then
        ISDebugMenu.setupButtons = hookRegistry.debugBase
        hookRegistry.debugWrapper, hookRegistry.debugBase = nil, nil
    else
        debugCanWrap = false -- outro mod esta por cima; preserve a cadeia
    end
end
local adminCanWrap = true
if hookRegistry.adminWrapper then
    if ISAdminPanelUI.create == hookRegistry.adminWrapper then
        ISAdminPanelUI.create = hookRegistry.adminBase
        hookRegistry.adminWrapper, hookRegistry.adminBase = nil, nil
    else
        adminCanWrap = false
    end
end

local function playerHasEditorAccess(player)
    local currentCore = PhunZones or Core
    -- Always allow in singleplayer
    if currentCore.isLocal then
        return true
    end
    local required = currentCore.getOption("EditorRole", "")
    if not required or required == "" then
        return true
    end
    local role = player and player.getRole and player:getRole()
    local roleName = role and role.getName and role:getName()
    if not roleName or roleName == "" then
        return false
    end
    return roleName:lower() == required:lower()
end

local function showPhunZonesConfigs()
    local currentCore = PhunZones or Core
    local player = getPlayer()
    if not playerHasEditorAccess(player) then
        local modal = ISModalDialog:new(0, 0, 300, 150, "Insufficient privileges to open the zone editor.", false, nil,
            nil, nil, nil, nil)
        modal:initialise()
        modal:addToUIManager()
        modal:setX((getCore():getScreenWidth() - modal:getWidth()) / 2)
        modal:setY((getCore():getScreenHeight() - modal:getHeight()) / 2)
        return
    end
    currentCore.ui.zones.OnOpenPanel(player)
end

if debugCanWrap then
local ISDebugMenu_setupButtons = ISDebugMenu.setupButtons
local function wrappedDebugSetupButtons(self)
    self:addButtonInfo("PhunZones", showPhunZonesConfigs, "MAIN")
    ISDebugMenu_setupButtons(self)
end
hookRegistry.debugBase = ISDebugMenu_setupButtons
hookRegistry.debugWrapper = wrappedDebugSetupButtons
ISDebugMenu.setupButtons = wrappedDebugSetupButtons
end

if adminCanWrap then
local ISAdminPanelUI_create = ISAdminPanelUI.create

-- b42
local function wrappedAdminCreate(self)

    local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
    local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
    local UI_BORDER_SPACING = 10
    local BUTTON_HGT = FONT_HGT_SMALL + 6

    local btnWid = 200;
    local x = UI_BORDER_SPACING + 1;
    local y = FONT_HGT_MEDIUM + UI_BORDER_SPACING * 2 + 1;

    self.showPhunZonesConfigs = ISButton:new(x, y, btnWid, BUTTON_HGT, "** PhunZones **", self, showPhunZonesConfigs);
    self.showPhunZonesConfigs.internal = "";
    self.showPhunZonesConfigs:initialise();
    self.showPhunZonesConfigs:instantiate();
    self.showPhunZonesConfigs.borderColor = self.buttonBorderColor;
    self:addChild(self.showPhunZonesConfigs);

    ISAdminPanelUI_create(self)

end
hookRegistry.adminBase = ISAdminPanelUI_create
hookRegistry.adminWrapper = wrappedAdminCreate
ISAdminPanelUI.create = wrappedAdminCreate
end
