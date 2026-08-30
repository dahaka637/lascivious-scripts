require("OptionScreens/SandboxOptions")
require("OptionScreens/ServerSettingsScreen")
require("ISUI/AdminPanel/ISServerSandboxOptionsUI")

---@alias ModOptions { [string]: zombie.config.ConfigOption }
---@alias ModToOptions { [string]: ModOptions }

WZUI_HOOKS = {}

---@type ModToOptions?
local modToOptions

---------------------------------------------------
-- Sandbox Options Screen Panel (SOLO) Overrides --
---------------------------------------------------

---@param self ISUIElement
local function sandboxOptionsScreenPanel_prerender(self)
    self:drawRectStatic(0, 0, self.width, self.height, 1, 0, 0, 0)
    self:setStencilRect(0, 0, self.width, self.height)
end

---@param self SandboxOptionsScreenPanel
local function sandboxOptionsScreenPanel_render(self)
    self:drawRectBorderStatic(0, 0, self.width, self.height, 1, 0.4, 0.4, 0.4)
    self:clearStencilRect()
    self.wzYScroll = math.abs(self:getYScroll())
end

----------------
-- Hook Match --
----------------

---@param screen SandboxOptionsScreen|ISServerSandboxOptionsUI|ServerSettingsScreen.Page3
---@param page table
---@param panel SandboxOptionsScreenPanel
---@return boolean
local function hookMatch(screen, page, panel)
    if panel.controls == nil  then
        print("hookMatch: no controls")
        return false
    end

    WZUI_TOOLTIP_MAX_WIDTH = panel:getWidth()

    if modToOptions == nil then
        modToOptions = {}
        local opt, name, key
        local options = getSandboxOptions()
        for i = 0, options:getNumOptions() - 1 do
            opt = options:getOptionByIndex(i) --[[@as zombie.config.ConfigOption]]
            name = opt:getName()
            key = string.match(name, "%a+%.")
            if key ~= nil then
                if modToOptions[key] == nil then modToOptions[key] = {} end
                modToOptions[key][name] = opt
            end
        end
    end

    for _, hook in pairs(WZUI_HOOKS) do
        if getText("Sandbox_" .. hook.key) == page.name then
            hook.obj:init(screen, panel, hook.key .. ".", modToOptions[hook.key .. "."])
            panel.wzHook = true
            panel.prerender = sandboxOptionsScreenPanel_prerender
            panel.render = sandboxOptionsScreenPanel_render
            return true
        end
    end

    return false
end

----------------
-- Solo Hooks --
----------------

local old_soloCreatePanel = SandboxOptionsScreen.createPanel
local function soloCreatePanel(self, page)
    local panel = old_soloCreatePanel(self, page)
    print("soloCreatePanel: " .. tostring(page.name))

    hookMatch(self, page, panel)
    return panel
end

SandboxOptionsScreen.createPanel = soloCreatePanel


local sandboxOptionsScreen_onPanelChange = SandboxOptionsScreen.onPanelChange
function SandboxOptionsScreen:onPanelChange()
    if self.currentPanel.wzHook then return end
    sandboxOptionsScreen_onPanelChange(self)
end

----------------
-- Admin Hook --
----------------

local old_adminCreateChildren = ISServerSandboxOptionsUI.createChildren
local function adminCreateChildren(self)
    old_adminCreateChildren(self)

    local item
    for _, lbitem in pairs(self.listbox.items) do
        item = lbitem.item
        item.panel.wzAdmin = true
        hookMatch(self, item.page, item.panel)
    end
end

ISServerSandboxOptionsUI.createChildren = adminCreateChildren

---------------
-- Host Hook --
---------------

local old_page3_onPanelChange
local function page3_onPanelChange(self)
    if self.currentPanel.wzHook then return end
    old_page3_onPanelChange(self)
end

local old_aboutToShow = ServerSettingsScreen.aboutToShow
local function aboutToShow(self)
    old_aboutToShow(self)

    for _, v in pairs(self.pageEdit.listbox.items) do
        if v.item.page ~= nil and v.item.panel ~= nil then
            hookMatch(self.pageEdit, v.item.page, v.item.panel)
        end
    end

    if self.pageEdit.onPanelChange ~= page3_onPanelChange then
        old_page3_onPanelChange = self.pageEdit.onPanelChange
        self.pageEdit.onPanelChange = page3_onPanelChange
    end
end

ServerSettingsScreen.aboutToShow = aboutToShow
