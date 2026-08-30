require("WZUI/RYUKU_WanderingZombies_UICommon")
require("WZUI/RYUKU_WanderingZombies_UIHooks")
require("RYUKU_WanderingZombies_Utility")

local optionGroups = {
    Shared_Pathing = {
        "MoveCooldownInitial",
        "WanderForwards",
        "OutOfCellPaths", "OutOfCellThreshold",
        "ForcePathfind",
        "HoursSurvived",
    },
    Shared_Exploration = {
        "RoomExploreLimit", "ForcedExploreChance", "DumbZombiesExplore", "ExploreDestructive"
    },
    Shared_Miscellaneous = { "ChebyshevDistance" }
}

---@class WZUIShared
WZUIShared = {}

---@param screen SandboxOptionsScreen
---@param panel SandboxOptionsScreenPanel
---@param key string
---@param modOptions ModToOptions
function WZUIShared:init(screen, panel, key, modOptions)
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

    -- OutOfCellThreshold should only be editable if OutOfCellPaths is
    local oocp = controlLookup[key .. "OutOfCellPaths"] --[[@as WZUICheckbox]]
    controlLookup[key .. "OutOfCellThreshold"]:setEnabledCondition(function(obj) return oocp:getValue() end)

    -- RoomExploreLimit controls whether or not exploration is enabled
    local exploreLimit = controlLookup[key .. "RoomExploreLimit"] --[[@as WZUITextbox]]
    exploreLimit:toggleWithGroup(false)
    wzuiGroups[2]:setEnabledCondition(function(obj) return exploreLimit:getNumberValue() > 0 end)

    -- DumbZombiesExplore requires Reflection Enabler
    local dumbExplore = controlLookup[key .. "DumbZombiesExplore"] --[[@as WZUICheckbox]]
    dumbExplore:setEnabledCondition(function(obj)
        if not WZUtility:isReflectionEnabled() then
            dumbExplore:setValue(true)
            return false
        end

        return true
    end)

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

table.insert(WZUI_HOOKS, { key = "WZShared", obj = WZUIShared })
