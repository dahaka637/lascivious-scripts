require("ISUI/ISTextBox")

local WeightManager = require("TotalWeightRebalance/apply_weights")
local options = PZAPI.ModOptions:create("TotalWeightRebalance", "Total Weight Rebalance")
local rightClickOption = options:addTickBox(
    "rightClickSetWeight",
    "Right click to set item weight",
    true,
    "Adds Set Weight to item context menus. In multiplayer only administrators can change weights."
)

local WeightDialog = ISTextBox:derive("TotalWeightRebalance_WeightDialog")

local function getSelectedItem(items)
    local item = items and items[1]
    if type(item) == "table" and item.items then item = item.items[1] end
    return item
end

local function submitWeight(_, button, playerNum, fullType)
    if button.internal ~= "OK" then return end
    local weight = tonumber(button.parent.entry:getText())
    if not weight or weight < 0 then return end
    WeightManager.setWeight(getSpecificPlayer(playerNum), fullType, weight)
end

local function validateWeight(_, value)
    local weight = tonumber(value)
    return weight ~= nil and weight >= 0 and weight < math.huge
end

local function usePresetWeight(dialog, button)
    WeightManager.setWeight(getSpecificPlayer(dialog.playerNum), dialog.fullType, button.weight)
    dialog:destroy()
end

local function addPresetButton(dialog, x, width, label, weight)
    local button = ISButton:new(x, dialog.yes:getBottom() + 10, width, 25, label, dialog, usePresetWeight)
    button.weight = weight
    button:initialise()
    button:instantiate()
    dialog:addChild(button)
    return button
end

function WeightDialog:initialise()
    ISTextBox.initialise(self)

    self.entry:setY(self:titleBarHeight() + 78)
    self.yes:setY(self.entry:getBottom() + 10)
    self.no:setY(self.yes:getY())
    self.yes:setTitle("Apply")

    local spacing = 10
    local buttonWidth = (self:getWidth() - spacing * 3) / 2
    local vanillaButton = addPresetButton(self, spacing, buttonWidth, "Vanilla Weight", self.vanillaWeight)
    addPresetButton(self, spacing * 2 + buttonWidth, buttonWidth, "TWR Weight", self.twrWeight)
    self:setHeight(vanillaButton:getBottom() + spacing)
end

function WeightDialog:prerender()
    ISTextBox.prerender(self)
    local x = 10
    local y = self:titleBarHeight() + 8
    local lineHeight = getTextManager():getFontHeight(UIFont.Small) + 5
    self:drawText("Vanilla weight: " .. WeightManager.formatWeight(self.vanillaWeight), x, y, 1, 1, 1, 1, UIFont.Small)
    self:drawText("TWR weight: " .. WeightManager.formatWeight(self.twrWeight), x, y + lineHeight, 1, 1, 1, 1, UIFont.Small)
    self:drawText("Current weight: " .. WeightManager.formatWeight(self.currentWeight), x, y + lineHeight * 2, 1, 1, 1, 1, UIFont.Small)
end

function WeightDialog:new(playerNum, fullType, vanillaWeight, twrWeight, currentWeight)
    local title = "Item ID: " .. fullType
    local dialog = ISTextBox:new(0, 0, 420, 230, title, WeightManager.formatWeight(currentWeight), nil, submitWeight, playerNum, playerNum, fullType)
    setmetatable(dialog, self)
    self.__index = self
    dialog.playerNum = playerNum
    dialog.fullType = fullType
    dialog.vanillaWeight = vanillaWeight
    dialog.twrWeight = twrWeight
    dialog.currentWeight = currentWeight
    return dialog
end

local function openWeightDialog(playerNum, fullType)
    local vanillaWeight = WeightManager.getOriginalWeight(fullType) or 0
    local twrWeight = WeightManager.getTwrWeight(fullType) or vanillaWeight
    local currentWeight = WeightManager.getWeight(fullType) or vanillaWeight
    local dialog = WeightDialog:new(playerNum, fullType, vanillaWeight, twrWeight, currentWeight)
    dialog:initialise()
    dialog:setValidateFunction(nil, validateWeight)
    dialog:addToUIManager()
end

local function canSetWeight()
    if not isClient() then return true end
    if isAdmin() then return true end
    return string.lower(tostring(getAccessLevel() or "")) == "admin"
end

local function addSetWeightOption(playerNum, context, items)
    if not rightClickOption:getValue() then return end
    if not canSetWeight() then return end

    local item = getSelectedItem(items)
    if not item or not item.getFullType then return end
    context:addOption("Set Weight", playerNum, openWeightDialog, item:getFullType())
end

Events.OnFillInventoryObjectContextMenu.Add(addSetWeightOption)
