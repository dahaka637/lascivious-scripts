--[[
    Burris Quality of Life -- stops inventory selections deselecting themselves.

    The bug and the row arithmetic are documented in
    shared/BQoL/BQoL_SelectionLogic.lua. This file is the wiring.

    Vanilla's restoreSelection is wrapped rather than replaced. The faulty
    assignment is mid-loop, so a wrapper cannot intercept it -- but it does not
    have to: running the correction as a second pass over the finished result
    reaches the same state, touches only the group rows, and leaves vanilla's
    handling of the individual items inside an expanded stack alone. A future
    42.x patch to that half then needs no merge here, which a whole-function
    copy would.

    Both inventory panes and the loot pane run this one function.
]]

require "BQoL/BQoL_Core"

--- Mods that already ship this fix; running both would be redundant, not harmful.
local CONFLICTS = { "NicksInventorySelectionFix" }

local function install()
    for _, modId in ipairs(CONFLICTS) do
        if BQoL.isModActive(modId) then
            BQoL.log("InventorySelection: standing down, %s is enabled", modId)
            return
        end
    end

    local original = ISInventoryPane and ISInventoryPane.restoreSelection
    if type(original) ~= "function" then
        BQoL.warn("InventorySelection: ISInventoryPane.restoreSelection is missing")
        return
    end

    function ISInventoryPane:restoreSelection(selected)
        original(self, selected)
        BQoL.Selection.upgradeGroupRows(self, selected)
    end
end

BQoL.feature{
    id = "InventorySelection",
    sandbox = "InventorySelectionFixEnabled",
    init = install,
}
