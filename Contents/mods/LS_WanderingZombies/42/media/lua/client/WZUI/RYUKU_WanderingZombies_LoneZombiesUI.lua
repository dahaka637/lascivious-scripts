require("WZUI/RYUKU_WanderingZombies_UICommon")
require("WZUI/RYUKU_WanderingZombies_UIHooks")

---@class WZUILoneZombies
WZUILoneZombies = {}

---@param screen SandboxOptionsScreen|ISServerSandboxOptionsUI|ServerSettingsScreen.Page3
---@param panel SandboxOptionsScreenPanel
---@param key string
---@param modOptions ModToOptions
function WZUILoneZombies:init(screen, panel, key, modOptions)
    -- remove existing controls
    panel.controls = WZUICommon.removeChildren(panel, panel.controls)
    panel.labels = WZUICommon.removeChildren(panel, panel.labels)

    -- build movement groups
    WZUI_GROUP_LABEL_WIDTH = 0
    local moveGroups = WZUICommon:createMoveGroups(screen, panel, key, modOptions)
    if moveGroups == nil then return end

    -- position and initialise groups
    local group, lastGroup
    local scrollHeight = 0
    for i = 1, #moveGroups do
        group = moveGroups[i]
        if i > 1 then
            lastGroup = moveGroups[i - 1]
            group:setY(lastGroup:getY() + lastGroup:getGroupHeight())
        end

        group:init()
        scrollHeight = scrollHeight + group:getGroupHeight()
    end

    panel:setScrollHeight(scrollHeight)
end

table.insert(WZUI_HOOKS, { key = "WZLoneZombie", obj = WZUILoneZombies })
