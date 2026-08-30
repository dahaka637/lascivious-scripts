--[[
    Burris Quality of Life -- tourniquet rules, shared between the health
    panel wiring and the timed action.

    Design constraint that shapes all of this: getRunSpeedModifier() and
    getWalkSpeedModifier() are getter-only from Lua -- there is no direct
    "slow the player down" call. The only real lever is RunSpeedModifier as a
    clothing item script property (Java sums it from what is worn), which is
    why a leg tourniquet is a genuine equippable item (BQoL_items.txt) and an
    arm tourniquet is not: arms get a one-time bleeding/pain adjustment only,
    with nothing ongoing to represent.
]]

require "BQoL/BQoL_Core"

BQoL.Tourniquet = BQoL.Tourniquet or {}
-- Files load in path order, not dependency order, so this cannot assume
-- BQoL_API.lua has already run.
BQoL.API = BQoL.API or {}

local Tourniquet = BQoL.Tourniquet

--[[
    Materials a tourniquet can be improvised from. Tag-free on purpose: unlike
    prying tools there is no vanilla "this is a belt" tag to key off, so this
    is a plain type list, extensible via BQoL.API.addTourniquetMaterial().
]]
local materials = {
    ["Base.Belt2"] = true,
    ["Base.RopeBelt"] = true,
}

function BQoL.API.addTourniquetMaterial(fullType)
    if type(fullType) ~= "string" or fullType == "" then
        BQoL.warn("addTourniquetMaterial: expected an item full type string")
        return false
    end
    materials[fullType] = true
    return true
end

function BQoL.API.getTourniquetMaterials()
    return materials
end

--[[
    Per-body-part configuration. Every part above the wrist/ankle routes to
    the nearest limb-root part: a hand wound and a forearm wound both tie off
    at the upper arm, matching how a real tourniquet is applied above the
    injury rather than at it.

    item is the BQoL_items.txt full type; nil for arms, which carry no
    clothing item at all. root marks the part a leg's single worn item is
    attributed to when nothing more specific is known -- see reconcile().
]]
local PART_CONFIG = {
    [BodyPartType.Hand_L]     = { side = "arm" },
    [BodyPartType.ForeArm_L]  = { side = "arm" },
    [BodyPartType.UpperArm_L] = { side = "arm" },
    [BodyPartType.Hand_R]     = { side = "arm" },
    [BodyPartType.ForeArm_R]  = { side = "arm" },
    [BodyPartType.UpperArm_R] = { side = "arm" },

    [BodyPartType.Foot_L]     = { side = "leg", location = ItemBodyLocation.THIGH_LEFT,  item = "Base.BQoL_TourniquetLeftLeg" },
    [BodyPartType.LowerLeg_L] = { side = "leg", location = ItemBodyLocation.THIGH_LEFT,  item = "Base.BQoL_TourniquetLeftLeg" },
    [BodyPartType.UpperLeg_L] = { side = "leg", location = ItemBodyLocation.THIGH_LEFT,  item = "Base.BQoL_TourniquetLeftLeg", root = true },
    [BodyPartType.Foot_R]     = { side = "leg", location = ItemBodyLocation.THIGH_RIGHT, item = "Base.BQoL_TourniquetRightLeg" },
    [BodyPartType.LowerLeg_R] = { side = "leg", location = ItemBodyLocation.THIGH_RIGHT, item = "Base.BQoL_TourniquetRightLeg" },
    [BodyPartType.UpperLeg_R] = { side = "leg", location = ItemBodyLocation.THIGH_RIGHT, item = "Base.BQoL_TourniquetRightLeg", root = true },
}

--[[
    The same table seen per leg rather than per body part: one worn item, worn
    at the thigh, covering whichever of the three parts was actually tied off.

    Derived rather than written out so it cannot drift from PART_CONFIG.
]]
local LEG_SIDES = {}

for partType, config in pairs(PART_CONFIG) do
    if config.side == "leg" then
        local side = LEG_SIDES[config.location]
        if not side then
            side = { location = config.location, item = config.item, parts = {} }
            LEG_SIDES[config.location] = side
        end
        table.insert(side.parts, partType)
        if config.root then side.root = partType end
    end
end

--- Returns the tourniquet config for a body part, or nil if it doesn't apply here.
function Tourniquet.configFor(bodyPart)
    if not bodyPart then return nil end
    return PART_CONFIG[bodyPart:getType()]
end

--- True when the part is actively bleeding, the standard vanilla check
--- (client/XpSystem/ISUI/ISHealthPanel.lua:784).
function Tourniquet.isBleeding(bodyPart)
    return bodyPart ~= nil and bodyPart:getBleedingTime() > 0
end

--- Finds a tourniquet material anywhere in the player's inventory, including bags.
function Tourniquet.findMaterial(playerObj)
    if not playerObj then return nil end
    local inventory = playerObj:getInventory()
    if not inventory then return nil end

    for fullType in pairs(materials) do
        local ok, item = BQoL.safe(
            "Tourniquet.findMaterial:" .. fullType,
            function() return inventory:getFirstTypeRecurse(fullType) end)
        if ok and item then return item end
    end

    return nil
end

--- True when a leg tourniquet is already worn in the given part's slot.
--- Distinct from getTied(): this asks whether the clothing item is in the slot,
--- not whether the limb is tied off.
function Tourniquet.isApplied(playerObj, config)
    if config.side ~= "leg" then return false end
    local worn = playerObj:getWornItems():getItem(config.location)
    return worn ~= nil and worn:getFullType() == config.item
end

--[[
    Takes the leg tourniquet's clothing item back off and destroys it.

    The unequip sequence is vanilla's own, lifted from ISUnequipAction:complete
    -- removeWornItem, sendEquip, then the OnClothingUpdated event, which is
    what makes the UI and the speed modifier notice. Doing only the first of
    those leaves the item off the body but the panel still showing it.

    The inventory sweep afterwards is not belt and braces: since the item stopped
    being hidden it can arrive here already unworn, sitting in a pocket because
    the player took it off through the clothing UI, and leaving it there would
    hand them a "Tourniquet" they could wear again for a free speed penalty.
]]
function Tourniquet.unwearLeg(patient, config)
    if not patient or not config or config.side ~= "leg" then return false end

    local removed = false

    local worn = patient:getWornItems():getItem(config.location)
    if worn and worn:getFullType() == config.item then
        patient:removeWornItem(worn)
        sendEquip(patient)
        triggerEvent("OnClothingUpdated", patient)
        removed = true
    end

    local inventory = patient:getInventory()
    if inventory then
        local ok, item = BQoL.safe("Tourniquet.unwearLeg",
            function() return inventory:getFirstTypeRecurse(config.item) end)

        if ok and item then
            --[[
                Removed from the container it is actually in rather than from
                the player's top-level one: getFirstTypeRecurse descends into
                bags and ItemContainer:Remove does not, so a strap that ended
                up inside one would survive a Remove aimed at the wrong
                container while this still reported success and the record was
                cleared -- leaving a wearable item with nothing recording it.
                Reachable now that the item is visible and can be moved, by the
                player or by an inventory-tidying mod, before the deferred
                untie runs.
            ]]
            local container = item:getContainer() or inventory
            container:Remove(item)
            if isServer() then
                sendRemoveItemFromContainer(container, item)
            end
            removed = true
        end
    end

    return removed
end

-- ------------------------------------------------------------------- maths

--[[
    Bleeding left after tying off, and what resumes when the tourniquet comes
    back off. release() is the exact inverse of tighten(), which is what stops
    tie/untie/re-tie from being a free way to drive a wound to zero with one
    belt -- and a wound that has since stopped bleeding divides up from 0 and
    stays there, so removal can never revive a healed limb.

    Pure functions rather than inline arithmetic so tools/test/tourniquet.lua
    can pin the round trip.
]]
function Tourniquet.tighten(bleedingTime, fraction)
    return (tonumber(bleedingTime) or 0) * (tonumber(fraction) or 1)
end

function Tourniquet.release(bleedingTime, fraction)
    -- BQoL.divide covers a corrupt or missing stored fraction: no bleeding
    -- comes back rather than dividing by zero.
    return BQoL.divide(tonumber(bleedingTime) or 0, fraction, 0)
end

--- Pain never goes below zero, however the stored figure drifted.
function Tourniquet.easePain(currentPain, added)
    local eased = (tonumber(currentPain) or 0) - (tonumber(added) or 0)
    if eased < 0 then return 0 end
    return eased
end

-- ------------------------------------------------------------------- state

--[[
    Which limbs are tied off, and with what, lives in the patient's mod data:

        patient:getModData().BQoL_Tourniquets = {
            ["7"] = { item = "Base.RopeBelt", pain = 20, bleed = 0.3 },
        }

    BodyPart carries no mod data of its own -- vanilla's splint gets away with
    bodyPart:setSplintItem() because that is a dedicated Java field -- so the
    patient is the only place to put it. Keys are body part indices as strings;
    mod data round-trips string keys reliably and numeric ones less so.

    pain and bleed are recorded per application rather than re-read from the
    sandbox on removal, so an admin retuning TourniquetBleedFraction mid-game
    cannot leave an already-tied limb unable to undo itself correctly.
]]
local MOD_DATA_KEY = "BQoL_Tourniquets"

local function tiedTable(patient, create)
    if not patient then return nil end

    local ok, modData = BQoL.safe("Tourniquet.getModData",
        function() return patient:getModData() end)
    if not ok or not modData then return nil end

    local tied = modData[MOD_DATA_KEY]
    if tied == nil and create then
        tied = {}
        modData[MOD_DATA_KEY] = tied
    end
    return tied
end

local function partKey(bodyPart)
    if not bodyPart then return nil end
    return tostring(bodyPart:getIndex())
end

--- The stored state for a tied-off limb, or nil when it is not tied off.
function Tourniquet.getTied(patient, bodyPart)
    local key = partKey(bodyPart)
    if not key then return nil end

    local tied = tiedTable(patient, false)
    if not tied then return nil end
    return tied[key]
end

function Tourniquet.setTied(patient, bodyPart, state)
    local key = partKey(bodyPart)
    if not key then return end

    local tied = tiedTable(patient, true)
    if not tied then return end
    tied[key] = state
end

function Tourniquet.clearTied(patient, bodyPart)
    local key = partKey(bodyPart)
    if not key then return end

    local tied = tiedTable(patient, false)
    if not tied then return end
    tied[key] = nil
end

--- Plain-table copy of every tied limb, safe to put on the wire.
function Tourniquet.snapshot(patient)
    local out = {}
    local tied = tiedTable(patient, false)
    if not tied then return out end

    for key, state in pairs(tied) do
        out[key] = { item = state.item, pain = state.pain, bleed = state.bleed, legacy = state.legacy }
    end
    return out
end

--- Overwrites the whole set. Used by the client when the server pushes state.
function Tourniquet.replaceAll(patient, parts)
    if not patient then return end

    local ok, modData = BQoL.safe("Tourniquet.getModData",
        function() return patient:getModData() end)
    if not ok or not modData then return end

    local tied = {}
    for key, state in pairs(parts or {}) do
        tied[tostring(key)] = { item = state.item, pain = state.pain, bleed = state.bleed, legacy = state.legacy }
    end
    modData[MOD_DATA_KEY] = tied
end

-- ---------------------------------------------------------- reconciliation

--[[
    Reconciliation between what is worn and what is recorded.

    Two things live here, and both exist because a leg tourniquet is two
    objects that have to agree: a record in the patient's mod data, and an
    invisible clothing item in the thigh slot.

      - A worn item with no record. Tourniquets applied before the state
        existed recorded nothing at all; on an arm that is unrecoverable, but a
        leg still has its item, and without a record there is no "- Tourniquet"
        line and no way to take it off.

      - A record with no worn item. Either an inert legacy record left behind
        (see below), or the player took the tourniquet off through the clothing
        UI, which is now a supported way to untie a limb.

      - Two records for one leg, one of them legacy. A leg carries one item and
        so earns one record; the legacy one is a phantom from an older build's
        reconciliation and goes whether or not the item is still worn.

    The item cannot say which of the three leg parts was tied, so an
    unattributed one goes to the limb root -- the same "tie off above the
    injury" rule PART_CONFIG already routes every leg wound through.

    Idempotent and cheap, which is what lets it be called from the paths that
    need it to have happened rather than from a player-spawn event that does
    not fire on a dedicated server.
]]

--[[
    True when this machine can believe what getWornItems() says about someone.

    On a multiplayer client another player's clothing arrives by sync and can
    lag behind their mod data, and this function deletes records on the
    strength of an item not being there. Repairing a doctor's view of a patient
    from a half-synced clothing list would take the removal option away from
    the one person able to use it. Own player, single player and the server all
    see the real thing.
]]
local function trustsWornItems(patient)
    if not isClient or not isClient() then return true end

    local ok, isLocal = BQoL.tryCall(patient, { "isLocalPlayer" })
    return ok and isLocal == true
end

--[[
    Brings records and worn items back into agreement.

    Returns changed, orphans -- changed is true when a record was written or
    dropped, and orphans is a list of body parts carrying a real record whose
    item is gone, which the caller is expected to untie properly (there is
    bleeding to restore and a belt to hand back, and on a multiplayer client
    neither is this machine's decision to make).
]]
function Tourniquet.reconcile(patient)
    if not patient then return false, nil end

    -- This runs on every push and every context menu, including for remote
    -- players mid-sync, so neither accessor is assumed to be there.
    local ok, damage = BQoL.safe("Tourniquet.reconcile",
        function() return patient:getBodyDamage() end)
    if not ok or not damage then return false, nil end

    local wornOk, wornItems = BQoL.safe("Tourniquet.reconcile",
        function() return patient:getWornItems() end)
    if not wornOk or not wornItems then return false, nil end

    local trusted = trustsWornItems(patient)
    local changed, orphans = false, nil

    for _, side in pairs(LEG_SIDES) do
        local worn = wornItems:getItem(side.location)
        local isOurs = worn ~= nil and worn:getFullType() == side.item

        -- Every record the leg carries, not just the limb root's: the item is
        -- worn at the thigh whichever part of the leg was tied off.
        local records = {}
        for _, partType in ipairs(side.parts) do
            local bodyPart = damage:getBodyPart(partType)
            local state = bodyPart and Tourniquet.getTied(patient, bodyPart)
            if state then
                table.insert(records, { part = bodyPart, state = state })
            end
        end

        --[[
            One item per leg means one legitimate record per leg -- isApplied
            already refuses a second tourniquet on a side that has one. A
            legacy record sitting alongside a real one is therefore provably
            the phantom the old root-only reconciliation grew, and it goes
            whichever way round the worn item is.

            That last part is what repairs a save whose tourniquet is still
            on. Dropping phantoms only once the item was gone left the player
            looking at two "- Tourniquet" lines on one leg until they removed
            the real one -- and if they took the phantom off first, untie()
            stripped the worn item out from under the record that was actually
            holding the wound, leaving its bleeding cut with nothing on the
            limb.

            A comparison between records and nothing else, so unlike the
            branches below it does not depend on trusting this machine's view
            of what is worn.
        ]]
        if #records > 1 then
            local hasReal = false
            for _, record in ipairs(records) do
                if not record.state.legacy then
                    hasReal = true
                    break
                end
            end

            if hasReal then
                local kept = {}
                for _, record in ipairs(records) do
                    if record.state.legacy then
                        Tourniquet.clearTied(patient, record.part)
                        changed = true
                        BQoL.log("dropped a phantom %s record", tostring(side.item))
                    else
                        table.insert(kept, record)
                    end
                end
                records = kept
            end
        end

        if isOurs then
            --[[
                Only when the leg has no record anywhere. Checking the limb
                root alone is what shipped, and it meant a tourniquet tied to a
                foot or a shin -- recorded on that part, worn at the thigh --
                left the root looking untied, so every run grew a second,
                phantom "- Tourniquet" line there. Removing the real one then
                left the phantom behind on a healed limb: a tourniquet that
                stayed on after removing, with no option to remove it.
            ]]
            if #records == 0 and side.root then
                local bodyPart = damage:getBodyPart(side.root)
                if bodyPart then
                    --[[
                        Deliberately inert. Which belt was consumed is
                        unknowable, so nothing is handed back rather than
                        conjuring a leather belt for someone who tied off with
                        rope; pain is 0 so removal cannot subtract a phantom
                        figure from an unrelated wound; and bleed is 1, not
                        nil, because release() divides -- a nil fraction would
                        hit BQoL.divide's zero fallback and silently stop the
                        bleeding instead of leaving it alone.
                    ]]
                    Tourniquet.setTied(patient, bodyPart,
                        { pain = 0, bleed = 1, legacy = true })
                    changed = true
                    BQoL.log("recorded a legacy %s tourniquet", tostring(side.item))
                end
            end
        elseif trusted then
            for _, record in ipairs(records) do
                if record.state.legacy then
                    --[[
                        Inert by definition -- no belt, no pain, no bleeding
                        held -- so dropping it is the entire repair, and it is
                        what heals a save already carrying a phantom.
                    ]]
                    Tourniquet.clearTied(patient, record.part)
                    changed = true
                    BQoL.log("dropped a stale legacy %s record", tostring(side.item))
                else
                    orphans = orphans or {}
                    table.insert(orphans, record.part)
                end
            end
        end
    end

    return changed, orphans
end

--[[
    Pushes the patient's tourniquet state to the clients that need it.

    On a multiplayer client LuaTimedActionNew.complete() skips the Lua
    complete() entirely -- it runs it only when GameClient.client is false --
    so the server is the sole writer of this state and nobody else would ever
    learn about it. Both the patient (their own health panel) and the doctor
    (treating someone else) need it.
]]
function Tourniquet.push(patient, doctor)
    if not isServer() or not patient then return end

    --[[
        Reconcile before snapshotting. replaceAll on the far side overwrites
        the client's whole set, so a push built from unreconciled server state
        would wipe out a legacy record the client had spotted for itself --
        taking the removal option away again.
    ]]
    Tourniquet.reconcile(patient)

    local args = { online = patient:getOnlineID(), parts = Tourniquet.snapshot(patient) }

    sendServerCommand(patient, BQoL.COMMAND_MODULE, "tourniquetState", args)
    if doctor and doctor ~= patient then
        sendServerCommand(doctor, BQoL.COMMAND_MODULE, "tourniquetState", args)
    end
end

-- ------------------------------------------------------------------ untying

--[[
    The bit mask both halves of the feature sync a body part with.

    syncBodyPart's flags are undocumented outside a comment convention vanilla
    actions follow -- e.g. ISRemoveBullet.lua:72's "BD_additionalPain +
    BD_bleedingTime + BD_bleeding + BD_haveBullet + BD_deepWounded +
    BD_deepWoundTime" = 0x40460108. There is no sample with just the two flags
    this feature needs, and guessing a narrower mask risks silently dropping
    the wrong field from the network sync in MP. That exact value is reused
    verbatim: it is confirmed to carry both BD_additionalPain and
    BD_bleedingTime, and the four extra flags it also marks dirty (bleeding,
    haveBullet, deepWounded, deepWoundTime) just resync their already-correct
    current values.
]]
Tourniquet.SYNC_MASK = 0x40460108

--[[
    Undoes a tourniquet: restores the bleeding it held, lifts the pain it
    added, takes the leg item back off, hands the belt to `recipient` and
    clears the record.

    Everything it needs is in the state the apply action recorded, so nothing
    is re-read from the current sandbox settings -- an admin retuning
    TourniquetBleedFraction mid-game cannot leave an already-tied limb unable
    to undo itself correctly.

    recipient is who gets the belt, and it differs by route: the health panel's
    removal hands it to the doctor, the way vanilla's ISSplint returns a
    removed splint to self.character, while a player who took the tourniquet
    off through the clothing UI gets it back themselves.
]]
function Tourniquet.untie(patient, bodyPart, recipient)
    if not patient or not bodyPart then return false end

    local state = Tourniquet.getTied(patient, bodyPart)
    if not state then return false end

    bodyPart:setBleedingTime(
        Tourniquet.release(bodyPart:getBleedingTime(), state.bleed))
    bodyPart:setAdditionalPain(
        Tourniquet.easePain(bodyPart:getAdditionalPain(), state.pain))

    -- A no-op on arms, and on a leg whose item is already off -- which is
    -- exactly the case when the clothing UI is what started this.
    local config = Tourniquet.configFor(bodyPart)
    if config then
        Tourniquet.unwearLeg(patient, config)
    end

    local inventory = recipient and recipient:getInventory()
    if state.item and inventory then
        local material = inventory:AddItem(state.item)
        if isServer() and material then
            sendAddItemToContainer(inventory, material)
        end
    end

    Tourniquet.clearTied(patient, bodyPart)

    syncBodyPart(bodyPart, Tourniquet.SYNC_MASK)
    Tourniquet.push(patient, recipient)

    return true
end
