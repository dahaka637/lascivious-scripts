require "BetterEngineRepairValues"
require "Vehicles/TimedActions/ISRepairEngine"

if not ISRepairEngine or type(ISRepairEngine.complete) ~= "function" then
    print("[Better Engine Repair B42] WARNING: ISRepairEngine:complete() was not found; patch not applied")
    return
end

-- B42.20.x keeps the repair amount local inside ISRepairEngine:complete(),
-- so there is no narrower helper to override. This replacement mirrors the
-- vanilla completion workflow and changes only condPerPart - it cannot call
-- through to a previous ISRepairEngine.complete the way a normal wrap would,
-- because vanilla's own condPerPart formula is inlined in that function; a
-- call-through would apply vanilla's repair amount on top of this mod's,
-- double-repairing the part.
--
-- LS_Traits' bundled Evolving Traits World wraps this same method with a
-- proper capture-before + call-through (measures condition before/after,
-- whatever the actual repair amount ends up being) to track Bodywork
-- Enthusiast/Mechanics trait progress - that wrap only sees this mod's real
-- repair amount if THIS file's flat reassignment runs first and ETW wraps
-- around it, never the other way around. LS_BetterEngineRepair must load
-- before LS_Traits in Mods= - see docs/COLLISION_REGISTRY.md and
-- docs/SERVER_MOD_ORDER.md (enforced once LS_Traits is actually wired in).
function ISRepairEngine:complete()
    if self.vehicle then
        if not self.part then
            noise("no such part Engine")
            return false
        end

        local mechanicsLevel = self.character:getPerkLevel(Perks.Mechanics)
        local numberOfParts = self.character:getInventory():getNumberOfItem("EngineParts", false, true)
        local giveXP = self.character:getMechanicsItem(self.part:getVehicle():getMechanicalID() .. "2") == nil
        local condPerPart = BetterEngineRepair.getConditionGain(mechanicsLevel)

        local done = 0
        for i = 1, numberOfParts do
            self.part:setCondition(self.part:getCondition() + condPerPart)
            done = done + 1

            if self.part:getCondition() >= 100 then
                self.part:setCondition(100)
                break
            end
        end

        if done > 0 then
            if giveXP then
                addXp(self.character, Perks.Mechanics, done)
            end

            local itemsToRemove = self.character:getInventory():getSomeTypeRecurse("EngineParts", done)
            for i = 0, itemsToRemove:size() - 1 do
                local item = itemsToRemove:get(i)
                local container = item:getContainer()
                if item and container then
                    container:DoRemoveItem(item)
                    sendRemoveItemFromContainer(container, item)
                end
            end

            self.vehicle:transmitPartCondition(self.part)
        else
            addXp(self.character, Perks.Mechanics, 1)
        end

        self.character:sendObjectChange(IsoObjectChange.MECHANIC_ACTION_DONE, { success = (done > 0) })
        if done > 0 then
            self.character:addMechanicsItem(self.item:getID() .. self.vehicle:getMechanicalID() .. "1", self.part, getGameTime():getCalender():getTimeInMillis())
        else
            addXp(self.character, Perks.Mechanics, 1)
        end

        self.character:addMechanicsItem(self.part:getVehicle():getMechanicalID() .. "2", self.part, getGameTime():getCalender():getTimeInMillis())
    else
        print("no such vehicle id=", self.vehicle)
        return false
    end

    return true
end
