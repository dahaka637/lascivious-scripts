--[[
    Burris Quality of Life -- picking up a piece of ground debris.

    Same anim, sound and duration formula as vanilla's own
    ISPickUpGroundCoverItem (shared/TimedActions/ISPickUpGroundCoverItem.lua),
    which this is deliberately kept close to so debris this mod covers feels
    identical to debris vanilla already covers. Differs in one respect:
    vanilla resolves a single item from the sprite's CustomName property with
    a chain of string comparisons; this resolves a list of { type, count }
    pairs from BQoL.API's debris mapping, so a sprite can grant more than one
    item and the mapping is directly inspectable/extensible rather than
    string-matched.
]]

require "TimedActions/ISBaseTimedAction"
require "BQoL/BQoL_Core"
require "BQoL/BQoL_API"

BQoL_CollectAction = ISBaseTimedAction:derive("BQoL_CollectAction")

function BQoL_CollectAction:isValid()
    return self.square:getObjects():contains(self.object)
end

function BQoL_CollectAction:waitToStart()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    return self.character:shouldBeTurning()
end

function BQoL_CollectAction:update()
    self.character:faceLocation(self.square:getX(), self.square:getY())
    self.character:setMetabolicTarget(Metabolics.DiggingSpade)
end

function BQoL_CollectAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    self:setOverrideHandModels(nil, nil)
    self.sound = self.character:playSound("CraftStonesRemove")
end

function BQoL_CollectAction:stopSound()
    if self.sound and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopOrTriggerSound(self.sound)
    end
end

function BQoL_CollectAction:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function BQoL_CollectAction:perform()
    self:stopSound()
    ISInventoryPage.renderDirty = true
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)
end

local function grantItem(player, fullType, count)
    if BQoL.getBool("CollectDisableLoot") then return end

    count = math.floor(count * BQoL.getNumber("CollectLootMultiplier"))
    if count <= 0 then return end

    for _ = 1, count do
        local item = instanceItem(fullType)
        if not item then return end

        if player:getInventory():hasRoomFor(player, item) then
            player:getInventory():AddItem(item)
            -- Unconditional, exactly as ISPickUpGroundCoverItem:complete() does
            -- it (:66, :79, :92). This action is queued from a client context
            -- menu and never runs on the server, so an isServer() guard here
            -- would mean the pickup is never transmitted: the sprite vanishes
            -- from the world but the item exists only in the client's local
            -- inventory until it relogs. (The guarded form does appear in
            -- vanilla -- ISApplyBandage:134, ISSplint:112 -- which is why
            -- BQoL_ApplyTourniquet uses it; those are server-run medical
            -- actions. This is not one of them.)
            sendAddItemToContainer(player:getInventory(), item)
        else
            local square = player:getCurrentSquare()
            local dropX, dropY, dropZ = ISTransferAction.GetDropItemOffset(player, square, item)
            square:SpawnWorldInventoryItem(fullType, dropX, dropY, dropZ)
        end
    end
end

function BQoL_CollectAction:complete()
    for _, entry in ipairs(self.items) do
        BQoL.safe("Collect.grant:" .. entry[1], grantItem, self.character, entry[1], entry[2])
    end

    self.object:getSquare():transmitRemoveItemFromSquare(self.object)
    return true
end

--[[
    Duration mirrors ISPickUpGroundCoverItem.grabItemTime2 -- weight of the
    first granted item, backpack fullness, DEXTROUS/ALL_THUMBS, instant-action
    debug. Not exposed as a Lua global outside that file, so reproduced here
    rather than reached into a sibling vanilla file that may not require it.
]]
function BQoL_CollectAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end

    --[[
        An API mapping may be an empty list -- documented as "removable but
        drops nothing" -- which leaves no first entry to weigh, and a consumer
        mod can register a fullType that does not resolve. Either must fall
        back to a plain weight of 1 rather than crash the moment the option
        is clicked. Vanilla guards the same path with `if trashItem then`.
    ]]
    local weight = 1
    local first = self.items[1]
    if first and ScriptManager.instance:getItem(first[1]) then
        weight = math.min(3, getItemActualWeight(first[1]))
    end

    local inv = self.character:getInventory()
    local capacityDelta = math.max(0.4, inv:getCapacityWeight() / inv:getMaxWeight())

    local maxTime = 120 * weight * capacityDelta

    if getCore():getGameMode() == "LastStand" then
        maxTime = maxTime * 0.3
    end
    if self.character:hasTrait(CharacterTrait.DEXTROUS) then
        maxTime = maxTime * 0.5
    end
    if self.character:hasTrait(CharacterTrait.ALL_THUMBS) or self.character:isWearingAwkwardGloves() then
        maxTime = maxTime * 2.0
    end

    return maxTime
end

function BQoL_CollectAction:new(character, square, object, items)
    local o = ISBaseTimedAction.new(self, character)

    o.character = character
    o.square = square
    o.object = object
    o.items = items
    o.maxTime = o:getDuration()

    return o
end
