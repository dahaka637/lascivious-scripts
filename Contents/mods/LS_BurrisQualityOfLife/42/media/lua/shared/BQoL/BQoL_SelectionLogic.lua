--[[
    Burris Quality of Life -- inventory selection restore, decision half.

    Vanilla loses a multi-stack selection whenever the pane refreshes, and it
    takes two refreshes to do it, which is why it reads as random.

    Every row in an inventory pane is a stack, a stack of one included, and
    selectIndex stores whatever sits at self.items[index] -- for a stack row
    that is the stack TABLE, not an item (ISInventoryPane.lua:332-335).
    restoreSelection (:2002-2021) puts the item back instead:

        if selected[item] == "group" then
            self.selected[row] = item      -- should be the stack table

    So the first refreshContainer swaps the kind of every whole-stack selection
    without changing how many rows are selected -- nothing looks wrong yet. The
    next saveSelection (:1981) then sees an InventoryItem where a stack was and
    records it as "item" rather than "group", and a collapsed stack offers no
    item row for the following restore to land on. The selection is gone. The
    item's quantity never entered into it.

    This file is the row walk with the assignment corrected. It is pure table
    arithmetic with no game API in it, which is the point: the bug is an
    off-by-one-kind, and the only way to see one of those without a player
    reporting it is to assert on it.
]]

BQoL = BQoL or {}
BQoL.Selection = BQoL.Selection or {}

--[[
    Re-points every whole-stack row at its stack table.

    Runs as a second pass over what vanilla's own restoreSelection just did, so
    only the group rows are touched and vanilla keeps ownership of the
    individual-item rows inside an expanded stack. A future 42.x patch to that
    half needs no merge here.

    `pane` is an ISInventoryPane, `selected` the map saveSelection built.
    Returns the number of rows corrected, for the tests and for debug logging.
]]
function BQoL.Selection.upgradeGroupRows(pane, selected)
    if type(pane) ~= "table" or type(selected) ~= "table" then return 0 end
    if type(pane.itemslist) ~= "table" or type(pane.selected) ~= "table" then return 0 end

    local collapsed = pane.collapsed or {}
    local row = 1
    local fixed = 0

    for _, stack in ipairs(pane.itemslist) do
        local items = stack.items
        if type(items) ~= "table" then return fixed end

        if selected[items[1]] == "group" then
            pane.selected[row] = stack
            fixed = fixed + 1
        end
        row = row + 1

        --[[
            An expanded stack occupies one row per item after its header, and
            those rows belong to vanilla. Only the row count is needed here --
            skipping them keeps this walk in step with the one above without
            duplicating what it decides.
        ]]
        if not collapsed[stack.name] then
            row = row + (#items - 1)
        end
    end

    return fixed
end
