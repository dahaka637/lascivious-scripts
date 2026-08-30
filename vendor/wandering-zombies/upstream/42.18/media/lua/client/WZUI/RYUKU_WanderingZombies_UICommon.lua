require("WZUI/RYUKU_WanderingZombies_UIGroup")

---@class WZUIControl
---@field package min WZUITextbox
---@field package max WZUITextbox
---@field package dropdown WZUIDropdown

---@class WZUICommon
WZUICommon = {}

---@param panel SandboxOptionsScreenPanel
---@param controls ISUIElement[]
---@return ISUIElement[]
function WZUICommon.removeChildren(panel, controls)
    for _, e in pairs(controls) do
        panel:removeChild(e)
    end

    return {}
end

---@param self WZUIControl
---@return boolean
function WZUICommon.isDropdownEnabled(self)
    return self.dropdown:isEnabled()
end

---@param self WZUIControl
---@return boolean
function WZUICommon.isDropdownRandom(self)
    return WZUICommon.isDropdownEnabled(self) and self.dropdown:getValue() == 2
end

---@param self WZUIControl
---@return boolean
function WZUICommon.isMovementEnabled(self)
    if self.dropdown:getValue() == 1 then return self.min:getNumberValue() > 0
    else return self.min:getNumberValue() > 0 or self.max:getNumberValue() > 0 end
end

---@param group WZUIGroup
---@param key string
---@param options ModOptions
---@param controlLookup { [string]: WZUIControl }
local function addMinMaxToGroup(group, key, options, controlLookup)
    local dropdown = group:createChild(options[key .. "Dropdown"])
    if dropdown == nil then return WZUICommon:error_createControl(key .. "Dropdown") end
    ---@cast dropdown WZUIDropdown
    controlLookup[key .. "Dropdown"] = dropdown

    local min = group:createChild(options[key .. "Min"])
    if min == nil then return WZUICommon:error_createControl(key .. "Min") end
    ---@cast min WZUITextbox
    controlLookup[key .. "Min"] = min
    min.dropdown = dropdown
    min:setEnabledCondition(WZUICommon.isDropdownEnabled)

    -- max should only be editable when Random is chosen
    local max = group:createChild(options[key .. "Max"])
    if max == nil then return WZUICommon:error_createControl(key .. "Max") end
    ---@cast max WZUITextbox
    controlLookup[key .. "Max"] = max
    max.dropdown = dropdown
    max:setEnabledCondition(WZUICommon.isDropdownRandom)

    -- chance min/max controls entire group editable state
    if key:find("Chance") ~= nil then
        group.dropdown = dropdown
        group.min = min
        group.max = max

        -- NOTE: getValue for min/max uses tonumber on the WZUITextbox value, so a nil check is required
        -- TODO: return 0 instead of nil?
        group:setEnabledCondition(WZUICommon.isMovementEnabled)
        dropdown:toggleWithGroup(false)
        min:toggleWithGroup(false)
        max:toggleWithGroup(false)
    end
end

---@param key string
function WZUICommon:error_createControl(key)
    print("WZUICommon: failed to create control - " .. key)
end

---@param screen SandboxOptionsScreen|ISServerSandboxOptionsUI|ServerSettingsScreen.Page3
---@param panel SandboxOptionsScreenPanel
---@param key string
---@param options ModOptions
---@param wzuiGroups WZUIGroup[]?
---@return WZUIGroup[]?, { [string]: WZUIControl }?
function WZUICommon:createMoveGroups(screen, panel, key, options, wzuiGroups)
    local moveGroups = wzuiGroups or {}
    local controlLookup = {}
    local moveAll = WZUIGroup:new(screen, panel, "Sandbox_WZGroupTitle_MovementAll")

    local wzuiControl
    for _, cdType in pairs({ "", "Random" }) do
        wzuiControl = moveAll:createChild(options[key .. "MoveCooldown" .. cdType])
        if wzuiControl == nil then return self:error_createControl(key .. "MoveCooldown" .. cdType) end
        controlLookup[key .. "MoveCooldown" .. cdType] = wzuiControl
    end

    wzuiControl = moveAll:createChild(options[key .. "MaxTravel"])
    if wzuiControl == nil then return self:error_createControl(key .. "MaxTravel") end
    controlLookup[key .. "MaxTravel"] = wzuiControl
    table.insert(moveGroups, moveAll)

    local group, groupKey
    for _, groupName in pairs({ "Wander", "Homing", "Flee" }) do
        group = WZUIGroup:new(screen, panel, "Sandbox_WZGroupTitle_Movement" .. groupName)
        groupKey = key .. groupName

        -- NOTE: since destructive is used for special movement, flag it to not disable with group
        -- TODO: maybe? probably should -- create destructive settings for special movement
        wzuiControl = group:createChild(options[groupKey .. "Destructive"])
        if wzuiControl == nil then return self:error_createControl(groupKey .. "Destructive") end
        controlLookup[groupKey .. "Destructive"] = wzuiControl
        wzuiControl:toggleWithGroup(false)

        -- build min/max settings
        for _, optionName in pairs({ "Chance", "StartHour", "TotalHours", "CooldownHours" }) do
            addMinMaxToGroup(group, groupKey .. optionName, options, controlLookup)
        end

        -- wandering does not have radius settings
        if groupName ~= "Wander" then
            addMinMaxToGroup(group, groupKey .. "Radius", options, controlLookup)
            wzuiControl = group:createChild(options[groupKey .. "RadiusInterrupt"])
            if wzuiControl == nil then return self:error_createControl(groupKey .. "RadiusInterrupt") end
            controlLookup[groupKey .. "RadisInterrupt"] = wzuiControl
        end

        table.insert(moveGroups, group)
    end

    return moveGroups, controlLookup
end
