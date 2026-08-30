--[[
    Burris Quality of Life -- walk while reading, and walk while dressing.

    Both follow the pattern vanilla itself uses for walk-friendly actions
    (ISEatFoodAction.lua:299): stopOnWalk = false, stopOnRun = true. The B42
    animation system keeps the action animation on the upper body and blends
    the walk cycle on the legs, so the reading pose is preserved.

    Wrapping happens inside init(): PZ rebuilds the Lua VM on every world
    load, so each load wraps a fresh vanilla original -- no stacked wrappers.
]]

require "BQoL/BQoL_Core"

BQoL.feature{
    id = "ReadWhileWalking",
    sandbox = "TweakReadWhileWalking",
    init = function()
        -- ISReadABook never sets stopOnWalk, so it inherits the
        -- ISBaseTimedAction default of true (ISReadABook.lua:483).
        local originalNew = ISReadABook.new
        function ISReadABook:new(character, item)
            local o = originalNew(self, character, item)
            o.stopOnWalk = false
            return o
        end
    end,
}

BQoL.feature{
    id = "EquipWhileWalking",
    sandbox = "TweakEquipWhileWalking",
    init = function()
        -- Vanilla already returns false for accessories (hats, glasses, bags,
        -- watches, ...); weapons equip while walking natively. This widens it
        -- to every wearable (ISWearClothing.lua:205).
        ISWearClothing.isStopOnWalk = function(item)
            return false
        end
    end,
}
