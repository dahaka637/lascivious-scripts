--[[
    Burris Quality of Life -- tying off a limb with a belt.

    Modelled on vanilla's ISApplyBandage/ISSplint: same doctor/patient split,
    same DidPatientMove abort check, same otherPlayer bookkeeping.

    The bleeding/pain adjustment happens in one shot in complete(), but it is
    not permanent: BQoL_RemoveTourniquet undoes it, hands back the belt this
    consumed, and takes off the leg clothing item that carries the movement
    penalty. Which belt to hand back is why complete() records the material
    type -- see BQoL_TourniquetLogic for where that lives and why.
]]

require "TimedActions/ISBaseTimedAction"
require "BQoL/BQoL_TourniquetLogic"

BQoL_ApplyTourniquet = ISBaseTimedAction:derive("BQoL_ApplyTourniquet")

function BQoL_ApplyTourniquet:isValid()
    if ISHealthPanel.DidPatientMove(self.character, self.otherPlayer,
        self.bandagedPlayerX, self.bandagedPlayerY) then
        return false
    end

    if isClient() then
        return self.itemWasPresent
    end
    return self.character:getInventory():contains(self.item)
        and BQoL.Tourniquet.isBleeding(self.bodyPart)
end

function BQoL_ApplyTourniquet:waitToStart()
    if self.character == self.otherPlayer then return false end
    self.character:faceThisObject(self.otherPlayer)
    return self.character:shouldBeTurning()
end

function BQoL_ApplyTourniquet:update()
    if self.character ~= self.otherPlayer then
        self.character:faceThisObject(self.otherPlayer)
    end
    -- The material can vanish between queue and start on a client (two
    -- tourniquet actions queued with a single belt): getItemById in start()
    -- then returns nil, and the client-side isValid() snapshot never catches
    -- it. Vanilla ISApplyBandage guards every self.item access; so do we.
    -- The server has its own way of losing the item; see complete().
    if self.item then
        self.item:setJobDelta(self:getJobDelta())
    end
    ISHealthPanel.setBodyPartActionForPlayer(self.otherPlayer, self.bodyPart,
        self, getText("ContextMenu_BQoL_ApplyTourniquet"), { bandage = true })
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function BQoL_ApplyTourniquet:start()
    -- Re-resolution can come back nil, and every self.item dereference in this
    -- file is guarded because of it. See the note above complete().
    if isClient() and self.item then
        self.item = self.character:getInventory():getItemById(self.item:getID())
    end

    if self.item then
        self.item:setJobType(getText("ContextMenu_BQoL_ApplyTourniquet"))
        self.item:setJobDelta(0.0)
    end

    if self.character == self.otherPlayer then
        self:setActionAnim(CharacterActionAnims.Bandage)
        self:setAnimVariable("BandageType", ISHealthPanel.getBandageType(self.bodyPart))
        self.character:reportEvent("EventBandage")
    else
        self:setActionAnim("Loot")
        self.character:SetVariable("LootPosition", "Mid")
        self.character:reportEvent("EventLootItem")
    end
    self:setOverrideHandModels(nil, nil)
end

function BQoL_ApplyTourniquet:stop()
    if self.item then
        self.item:setJobDelta(0.0)
    end
    ISHealthPanel.setBodyPartActionForPlayer(self.otherPlayer, self.bodyPart, nil, nil, nil)
    ISBaseTimedAction.stop(self)
end

function BQoL_ApplyTourniquet:perform()
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)
    if self.item then
        self.item:setJobDelta(0.0)
    end
    ISHealthPanel.setBodyPartActionForPlayer(self.otherPlayer, self.bodyPart, nil, nil, nil)
end

--[[
    Runs on the server in multiplayer, never on the client (LuaTimedActionNew
    calls it only when GameClient.client is false).

    The server rebuilds this action from serialised constructor arguments and
    resolves self.item through ItemContainer.getItemWithID, which yields nil
    when the item is not where the client said it was. Dereferencing that nil
    is exactly what killed Replace Bandage inside NetTimedAction.perform, so
    bail out cleanly instead of tying off a limb with nothing.
]]
function BQoL_ApplyTourniquet:complete()
    if not self.item then
        BQoL.warn("ApplyTourniquet: material did not resolve; not applying")
        return false
    end

    local config = BQoL.Tourniquet.configFor(self.bodyPart)
    if not config then return true end

    -- Read before Remove: the item is gone by the time the state is recorded,
    -- and the whole point is to remember which belt to hand back.
    local materialType = self.item:getFullType()
    local bleedFraction = BQoL.getNumber("TourniquetBleedFraction")
    local pain = BQoL.getNumber("TourniquetPain")

    self.bodyPart:setBleedingTime(
        BQoL.Tourniquet.tighten(self.bodyPart:getBleedingTime(), bleedFraction))
    self.bodyPart:setAdditionalPain(self.bodyPart:getAdditionalPain() + pain)

    -- Unguarded, unlike every other self.item access in this file: the early
    -- return above already established there is one.
    self.character:getInventory():Remove(self.item)
    if isServer() then
        sendRemoveItemFromContainer(self.character:getInventory(), self.item)
    end

    BQoL.Tourniquet.setTied(self.otherPlayer, self.bodyPart, {
        item = materialType,
        pain = pain,
        bleed = bleedFraction,
    })

    if config.side == "leg" and not BQoL.Tourniquet.isApplied(self.otherPlayer, config) then
        local tourniquetItem = instanceItem(config.item)
        -- instanceItem returns nil when the script item failed to load;
        -- AddItem(nil) would crash an otherwise successful application.
        if tourniquetItem then
            self.otherPlayer:getInventory():AddItem(tourniquetItem)
            if isServer() then
                sendAddItemToContainer(self.otherPlayer:getInventory(), tourniquetItem)
            end

            --[[
                Worn here and now, not queued as an ISWearClothing behind this
                action, and the record above and the item have to land in the
                same breath for two separate reasons.

                The first is that a dedicated server -- where this complete()
                is the only one that runs -- has no ISTimedActionQueue to put
                a wearing action on, and reaching for it raised before
                syncBodyPart and Tourniquet.push below ever ran. A leg
                tourniquet then applied its bleed and pain and synced none of
                it, leaving an item in the patient's inventory that nobody was
                wearing.

                The second is why the queued branch went away everywhere else
                too. ISWearClothing takes 50 ticks (ISWearClothing.lua:143) and
                announces nothing when it finishes, so queueing it left a
                window where the limb had a record and no worn item -- which is
                exactly the shape Tourniquet.reconcile reads as "the player
                took this off through the clothing UI". Anything that
                reconciled in that window (another right-click on the limb, any
                OnClothingUpdated from equipping a weapon) undid the tourniquet
                that had just been paid for, and then the wear action equipped
                the item anyway. The invariant reconcile is built on is that a
                record and its item are written together; this keeps it.

                setWornItem is what ISWearClothing:complete() itself calls, so
                nothing is lost but the animation -- and this action already
                played one for its whole duration.
            ]]
            BQoL.safe("ApplyTourniquet.wear", function()
                self.otherPlayer:setWornItem(config.location, tourniquetItem)
            end)
        end
    end

    -- The mask, and why it is that exact value, are documented alongside it
    -- in BQoL_TourniquetLogic.
    syncBodyPart(self.bodyPart, BQoL.Tourniquet.SYNC_MASK)

    -- The state above was just written server-side; syncBodyPart does not
    -- carry mod data, so the clients have to be told separately.
    BQoL.Tourniquet.push(self.otherPlayer, self.character)

    return true
end

function BQoL_ApplyTourniquet:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 100 - (self.doctorLevel * 4)
end

function BQoL_ApplyTourniquet:new(character, otherPlayer, item, bodyPart)
    local o = ISBaseTimedAction.new(self, character)

    o.character = character
    o.otherPlayer = otherPlayer
    o.doctorLevel = character:getPerkLevel(Perks.Doctor)
    o.item = item
    o.bodyPart = bodyPart
    o.bandagedPlayerX = otherPlayer:getX()
    o.bandagedPlayerY = otherPlayer:getY()
    o.itemWasPresent = item ~= nil
    o.maxTime = o:getDuration()

    -- Vanilla lets you keep walking while bandaging a leg; a leg tourniquet
    -- gets the same treatment (ISApplyBandage.lua:181).
    o.stopOnWalk = bodyPart:getIndex() > BodyPartType.ToIndex(BodyPartType.Groin)

    if isMultiplayer() and character:getRole():hasCapability(Capability.CanMedicalCheat) then
        o.doctorLevel = 10
    end

    return o
end
