require("WZUI/RYUKU_WanderingZombies_UICommon")
require("WZUI/RYUKU_WanderingZombies_UIHooks")
require("RYUKU_WanderingZombies_Utility")

local numOptionGroups = 3
local optionGroups = {
    Horde_Core = { "Hordes", "WorldAgeHours", "HordeSize", "HordeLimit", "CreateJoinMergeDistance", "LeaveDistance" },
    Horde_Merging = { "HordesMerge", "MergeCooldown" },
    Horde_Speed = { "GroupBySpeed", "AllowSprinters", "AllowFastShamblers", "AllowShamblers", "AllowCrawlers" },
}

---@class WZUIControl
---@field package hordesCheckbox WZUICheckbox?
---@field package mergeCheckbox WZUICheckbox?

---@param self WZUIControl
local function areHordesEnabled(self)
    return self.hordesCheckbox:getValue()
end

---@class WZUIHordeZombies
WZUIHordeZombies = {}

---@param screen SandboxOptionsScreen|ISServerSandboxOptionsUI|ServerSettingsScreen.Page3
---@param panel SandboxOptionsScreenPanel
---@param key string
---@param modOptions ModToOptions
function WZUIHordeZombies:init(screen, panel, key, modOptions)
    -- remove existing controls
    panel.controls = WZUICommon.removeChildren(panel, panel.controls)
    panel.labels = WZUICommon.removeChildren(panel, panel.labels)

    -- build horde option groups
    WZUI_GROUP_LABEL_WIDTH = 0
    local wzuiGroups = {} ---@type WZUIGroup[]
    local controlLookup = {} ---@type { [string]: WZUIControl }?
    local group, wzuiControl, hordesCheckbox
    for groupKey, optionKeys in pairs(optionGroups) do
        group = WZUIGroup:new(screen, panel, "Sandbox_WZGroupTitle_" .. groupKey)
        for _, okey in pairs(optionKeys) do
            wzuiControl = group:createChild(modOptions[key .. okey])
            if wzuiControl == nil then return WZUICommon:error_createControl(key .. okey)
            elseif okey == "Hordes" then
                wzuiControl:canToggle(false)
                hordesCheckbox = wzuiControl --[[@as WZUICheckbox]]
            end

            controlLookup[key .. okey] = wzuiControl
        end

        table.insert(wzuiGroups, group)
    end

    -- merge cooldown needs to toggle with merge checkbox
    if controlLookup == nil then return end
    wzuiControl = controlLookup[key .. "MergeCooldown"]
    wzuiControl.mergeCheckbox = controlLookup[key .. "HordesMerge"] --[[@as WZUICheckbox]]
    wzuiControl:setEnabledCondition(function(obj) return obj.mergeCheckbox:getValue() end)

    -- build movement groups
    if hordesCheckbox == nil then return end
    local combinedGroups = nil
    combinedGroups, controlLookup = WZUICommon:createMoveGroups(screen, panel, key, modOptions, wzuiGroups)
    if combinedGroups == nil or controlLookup == nil then return end

    -- chance/destructive dropdowns don't toggle with their group, they need their own condition
    -- chance dropdowns are checked by their paired min/max conditions
    for _, mkey in pairs({ "Wander", "Homing", "Flee" }) do
        for _, okey in pairs({ "ChanceDropdown", "Destructive" }) do
            wzuiControl = controlLookup[key .. mkey .. okey]
            wzuiControl.hordesCheckbox = hordesCheckbox
            wzuiControl:setEnabledCondition(areHordesEnabled)
        end
    end

    -- create Cooldown: Horde Size
    group = combinedGroups[numOptionGroups + 1]
    wzuiControl = group:createChild(modOptions[key .. "MoveCooldownHordeSize"])
    if wzuiControl == nil then return WZUICommon:error_createControl(key .. "MoveCooldownHordeSize") end
    group:swapChildren(3, 4)

    -- position and initialise groups
    local lastGroup
    local scrollHeight = 0
    for i = 1, #combinedGroups do
        group = combinedGroups[i]

        -- movement groups already have their own condition, and need to be adjusted
        group.hordesCheckbox = hordesCheckbox
        if group:hasCondition() and i > 3 then
            group:setEnabledCondition(function(obj)
                return areHordesEnabled(obj) and WZUICommon.isMovementEnabled(obj)
            end)
        else group:setEnabledCondition(areHordesEnabled) end

        if i > 1 then
            lastGroup = combinedGroups[i - 1]
            group:setY(lastGroup:getY() + lastGroup:getGroupHeight())
        end

        group:init()
        scrollHeight = scrollHeight + group:getGroupHeight()
    end

    panel:setScrollHeight(scrollHeight)
end

table.insert(WZUI_HOOKS, { key = "WZHordeZombie", obj = WZUIHordeZombies })
