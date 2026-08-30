require("WZUI/RYUKU_WanderingZombies_UICommon")
require("WZUI/RYUKU_WanderingZombies_UIHooks")

local optionGroups = {
    Director_PullEvent = { "PullEnabled", "PullUnseenTime", "PullMinRadius", "PullMaxRadius" },
    Director_MigrateEvent = { "MigrateEnabled", "MigrateDistance", "MigrateZombieThreshold", "MigrateCooldown" },
}

---@class WZUIDirector
WZUIDirector = {}

---@param screen SandboxOptionsScreen|ISServerSandboxOptionsUI|ServerSettingsScreen.Page3
---@param panel SandboxOptionsScreenPanel
---@param key string
---@param modOptions ModToOptions
function WZUIDirector:init(screen, panel, key, modOptions)
    -- remove existing controls
    panel.controls = WZUICommon.removeChildren(panel, panel.controls)
    panel.labels = WZUICommon.removeChildren(panel, panel.labels)

    -- build groups
    WZUI_GROUP_LABEL_WIDTH = 0
    local wzuiGroups = {}
    local controlLookup = {} ---@type { [string]: WZUIControl }
    local group, wzuiControl
    for groupKey, optionKeys in pairs(optionGroups) do
        group = WZUIGroup:new(screen, panel, "Sandbox_WZGroupTitle_" .. groupKey)
        for _, okey in pairs(optionKeys) do
            wzuiControl = group:createChild(modOptions[key .. okey])
            if wzuiControl == nil then return WZUICommon:error_createControl(key .. okey) end
            controlLookup[key .. okey] = wzuiControl
        end

        table.insert(wzuiGroups, group)
    end

    local enabled
    for idx, name in pairs({ "Pull", "Migrate" }) do
        enabled = controlLookup[key .. name .. "Enabled"] --[[@as WZUICheckbox]]
        enabled:toggleWithGroup(false)
        wzuiGroups[idx]:setEnabledCondition(function(obj) return obj._children[1]:getValue() end)
    end

    -- position and initialise groups
    local lastGroup
    local scrollHeight = 0
    for i = 1, #wzuiGroups do
        group = wzuiGroups[i]
        if i > 1 then
            lastGroup = wzuiGroups[i - 1]
            group:setY(lastGroup:getY() + lastGroup:getGroupHeight())
        end

        group:init()
        scrollHeight = scrollHeight + group:getGroupHeight()
    end

    panel:setScrollHeight(scrollHeight)
end

table.insert(WZUI_HOOKS, { key = "WZDirector", obj = WZUIDirector })
