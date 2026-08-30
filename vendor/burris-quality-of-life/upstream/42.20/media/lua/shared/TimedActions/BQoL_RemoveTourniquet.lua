--[[
    Burris Quality of Life -- untying a tourniquet.

    The counterpart to BQoL_ApplyTourniquet, shaped like vanilla's own removal
    half (ISSplint with doIt = false): undo the effect, hand the material back
    to the doctor, clear the state.

    Everything it needs is in the state the apply action recorded, so this
    action takes no item -- which belt comes back, how much pain to lift and
    which bleed fraction to invert are all read from there rather than from the
    current sandbox settings.

    The undo itself is BQoL.Tourniquet.untie, because this is no longer the
    only way to take a tourniquet off: unequipping the leg item through the
    clothing UI runs the same code, and the two must not drift.
]]

require "TimedActions/ISBaseTimedAction"
require "BQoL/BQoL_TourniquetLogic"

BQoL_RemoveTourniquet = ISBaseTimedAction:derive("BQoL_RemoveTourniquet")

function BQoL_RemoveTourniquet:isValid()
    if ISHealthPanel.DidPatientMove(self.character, self.otherPlayer,
        self.bandagedPlayerX, self.bandagedPlayerY) then
        return false
    end

    -- Cached on the client for the same reason vanilla caches itemWasPresent:
    -- the authoritative state lives on the server and arrives by push, so a
    -- live re-read here could drop the action mid-way on a slow sync.
    if isClient() then
        return self.wasTied
    end
    return BQoL.Tourniquet.getTied(self.otherPlayer, self.bodyPart) ~= nil
end

function BQoL_RemoveTourniquet:waitToStart()
    if self.character == self.otherPlayer then return false end
    self.character:faceThisObject(self.otherPlayer)
    return self.character:shouldBeTurning()
end

function BQoL_RemoveTourniquet:update()
    if self.character ~= self.otherPlayer then
        self.character:faceThisObject(self.otherPlayer)
    end
    ISHealthPanel.setBodyPartActionForPlayer(self.otherPlayer, self.bodyPart,
        self, getText("ContextMenu_BQoL_RemoveTourniquet"), { bandage = true })
    self.character:setMetabolicTarget(Metabolics.LightDomestic)
end

function BQoL_RemoveTourniquet:start()
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

function BQoL_RemoveTourniquet:stop()
    ISHealthPanel.setBodyPartActionForPlayer(self.otherPlayer, self.bodyPart, nil, nil, nil)
    ISBaseTimedAction.stop(self)
end

function BQoL_RemoveTourniquet:perform()
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)
    ISHealthPanel.setBodyPartActionForPlayer(self.otherPlayer, self.bodyPart, nil, nil, nil)
end

function BQoL_RemoveTourniquet:complete()
    -- The client offered this option off its own reconciled copy; the server
    -- decides what actually happens and may not have reconciled yet.
    BQoL.Tourniquet.reconcile(self.otherPlayer)

    -- Back to the doctor, not the patient -- vanilla's ISSplint returns a
    -- removed splint to self.character the same way. The rest of the undo,
    -- shared with the clothing-UI route, lives in BQoL_TourniquetLogic.
    BQoL.Tourniquet.untie(self.otherPlayer, self.bodyPart, self.character)

    return true
end

function BQoL_RemoveTourniquet:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    -- Untying is quicker than tying: no material to position, nothing to
    -- judge. Roughly half the apply action's 100 - level * 4.
    return 50 - (self.doctorLevel * 2)
end

function BQoL_RemoveTourniquet:new(character, otherPlayer, bodyPart)
    local o = ISBaseTimedAction.new(self, character)

    o.character = character
    o.otherPlayer = otherPlayer
    o.doctorLevel = character:getPerkLevel(Perks.Doctor)
    o.bodyPart = bodyPart
    o.bandagedPlayerX = otherPlayer:getX()
    o.bandagedPlayerY = otherPlayer:getY()
    o.wasTied = BQoL.Tourniquet.getTied(otherPlayer, bodyPart) ~= nil
    o.maxTime = o:getDuration()

    -- Matches BQoL_ApplyTourniquet, which follows ISApplyBandage.lua:181:
    -- a leg can be worked on while walking. Untying has to be at least as
    -- permissive as tying, or a limb you could tie on the move traps you
    -- standing still to undo it.
    o.stopOnWalk = bodyPart:getIndex() > BodyPartType.ToIndex(BodyPartType.Groin)

    if isMultiplayer() and character:getRole():hasCapability(Capability.CanMedicalCheat) then
        o.doctorLevel = 10
    end

    return o
end
