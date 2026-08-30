--[[
    Burris Quality of Life -- "Apply Tourniquet" / "Remove Tourniquet" on a limb.

    Same wrap as BQoL_ReplaceBandage, through BQoL_HealthMenu: the vanilla
    function is file-local, so the only way in is to let the original build its
    menu and append after -- and then undo the hide the original performs on a
    menu it found empty, which is what left tourniquets on limbs with no way to
    take them off. BQoL_HealthMenu documents that trap in full.

    Two more vanilla surfaces get wrapped here, both so a tourniquet is
    something the player can actually see and undo rather than an unexplained
    speed penalty and a belt that vanished:

      - ISHealthBodyPartListBox:doDrawItem, for the "- Tourniquet" status line.
        It returns its own row height (ISHealthPanel.lua:848 ends in
        `y = y + 5; return y`), so a line can be appended by drawing into that
        trailing pad and re-adding the pad afterwards.

      - ISHealthPanel:getDamagedParts, so a tied-off limb stays in the list.
        Vanilla lists a part only while it is injured, bandaged, stitched,
        splinted, stiff or hurting (line 523) -- once the wound heals and the
        pain decays, the limb would drop off the panel and take the only way to
        untie it with it.
]]

require "BQoL/BQoL_Core"
require "BQoL/BQoL_HealthMenu"
require "BQoL/BQoL_TourniquetLogic"
require "TimedActions/BQoL_ApplyTourniquet"
require "TimedActions/BQoL_RemoveTourniquet"

local function onApplySelected(target, doctor, patient, bodyPart)
    -- Re-found at click time: both may have changed since the menu opened.
    local material = BQoL.Tourniquet.findMaterial(doctor)
    if not material then return end
    if not BQoL.Tourniquet.isBleeding(bodyPart) then return end
    if BQoL.Tourniquet.getTied(patient, bodyPart) then return end

    ISInventoryPaneContextMenu.transferIfNeeded(doctor, material)
    ISTimedActionQueue.add(
        BQoL_ApplyTourniquet:new(doctor, patient, material, bodyPart))
end

local function onRemoveSelected(target, doctor, patient, bodyPart)
    if not BQoL.Tourniquet.getTied(patient, bodyPart) then return end

    ISTimedActionQueue.add(
        BQoL_RemoveTourniquet:new(doctor, patient, bodyPart))
end

--[[
    Finishes a removal the player started through the clothing UI.

    Since the leg tourniquet stopped being a hidden item, unequipping it is a
    legitimate way to untie the limb -- so it has to do everything the health
    panel's own removal does: give the bleeding back, lift the pain, hand the
    belt over. Doing nothing would leave a limb recorded as tied off with no
    item on it; dropping the record silently would be a free, permanent bleed
    cut for one right-click.
]]
local function resolveOrphans(patient, orphans)
    if not orphans or not patient then return end

    --[[
        The server owns this state in multiplayer (see the note above
        Tourniquet.push), so a client asks rather than acts. The server derives
        the orphan list itself from the clothing the client already synced with
        sendEquip, which is why nothing about the limbs is sent here.
    ]]
    if isClient() then
        sendClientCommand(patient, BQoL.COMMAND_MODULE, "tourniquetUnequipped",
            { online = patient:getOnlineID() })
        return
    end

    for _, bodyPart in ipairs(orphans) do
        BQoL.Tourniquet.untie(patient, bodyPart, patient)
    end
end

-- --------------------------------------------------------------- context menu

local function installMenu()
    local original = ISHealthPanel.doBodyPartContextMenu

    function ISHealthPanel:doBodyPartContextMenu(bodyPart, x, y)
        original(self, bodyPart, x, y)

        local config = BQoL.Tourniquet.configFor(bodyPart)
        if not config then return end

        local doctor = self.otherPlayer or self.character
        local patient = self.character
        if not doctor or not patient then return end

        -- Cheap and idempotent. BQoL_RemoveTourniquet caches wasTied in its
        -- constructor and clients trust that cache, so the record has to exist
        -- before the option that builds the action is even drawn.
        local _, orphans = BQoL.Tourniquet.reconcile(patient)
        resolveOrphans(patient, orphans)

        local context, playerNum = BQoL.HealthMenu.get(self)
        if not context then return end

        --[[
            A limb that is already tied off offers removal and nothing else.
            The early return is also the guard against stacking: before the
            state existed only legs were protected (by the worn-item check),
            so an arm could be tied off over and over, burning a belt each
            time for another compounding bleed cut.
        ]]
        local tied = BQoL.Tourniquet.getTied(patient, bodyPart)
        if tied then
            local option = context:addOption(getText("ContextMenu_BQoL_RemoveTourniquet"),
                nil, onRemoveSelected, doctor, patient, bodyPart)

            -- A legacy tourniquet cannot say which belt it was made from,
            -- so nothing comes back. Say so rather than let the player expect
            -- a belt that never arrives.
            BQoL.tooltip(option, tied.legacy
                and getText("Tooltip_BQoL_RemoveTourniquetLegacy")
                or getText("Tooltip_BQoL_RemoveTourniquet"))

            -- The whole point: a limb whose wound has healed gives vanilla
            -- nothing to offer, and vanilla hides an empty menu.
            BQoL.HealthMenu.reveal(self, context, playerNum)
            return
        end

        if not BQoL.Tourniquet.isBleeding(bodyPart) then return end
        if config.side == "leg" and BQoL.Tourniquet.isApplied(patient, config) then
            return
        end
        if not BQoL.Tourniquet.findMaterial(doctor) then return end

        local option = context:addOption(getText("ContextMenu_BQoL_ApplyTourniquet"),
            nil, onApplySelected, doctor, patient, bodyPart)

        BQoL.tooltip(option, config.side == "leg"
            and getText("Tooltip_BQoL_TourniquetLeg")
            or getText("Tooltip_BQoL_TourniquetArm"))

        -- Same hide, reached the other way: a doctor carrying a belt but no
        -- bandage has nothing vanilla wants to offer for a bleeding limb.
        BQoL.HealthMenu.reveal(self, context, playerNum)
    end
end

-- ------------------------------------------------------------- health panel

local function installPanel()
    local originalDraw = ISHealthBodyPartListBox.doDrawItem
    local fontHgtSmall = getTextManager():getFontHeight(UIFont.Small)

    function ISHealthBodyPartListBox:doDrawItem(y, item, alt)
        local bottom = originalDraw(self, y, item, alt)

        local healthPanel = self.parent
        local bodyPart = item and item.item and item.item.bodyPart
        if not healthPanel or not bodyPart then return bottom end

        local patient = healthPanel:getPatient()
        if not patient or not BQoL.Tourniquet.getTied(patient, bodyPart) then
            return bottom
        end

        -- x = 15 and the green of the other treatment lines (Bandaged,
        -- Splinted) rather than the red of the injuries above them.
        local lineY = bottom - 5
        self:drawText("- " .. getText("IGUI_BQoL_Tourniquet"), 15, lineY,
            0.28, 0.89, 0.28, 1, UIFont.Small)
        return lineY + fontHgtSmall + 5
    end

    local originalParts = ISHealthPanel.getDamagedParts

    function ISHealthPanel:getDamagedParts()
        local parts = originalParts(self)

        local patient = self:getPatient()
        if not patient then return parts end

        local listed = {}
        for _, part in ipairs(parts) do listed[part] = true end

        -- Mirrors vanilla's own remote-patient handling one function up.
        local bodyParts = patient:getBodyDamage():getBodyParts()
        if isClient() and not patient:isLocalPlayer() then
            bodyParts = patient:getBodyDamageRemote():getBodyParts()
        end

        local added = false
        for i = 1, bodyParts:size() do
            local part = bodyParts:get(i - 1)
            if not listed[part] and BQoL.Tourniquet.getTied(patient, part) then
                table.insert(parts, part)
                added = true
            end
        end

        -- Vanilla builds its list in body part order; sorting restores that
        -- rather than leaving our additions bunched at the bottom.
        if added then
            table.sort(parts, function(a, b) return a:getIndex() < b:getIndex() end)
        end

        return parts
    end
end

-- ---------------------------------------------------------------- MP sync

--[[
    The server owns the tourniquet state -- on a multiplayer client the Lua
    complete() of a timed action never runs -- so it pushes the patient's whole
    set here whenever it changes. Shaped like BQoL_Commands.lua's dispatch on
    the other side of the wire.
]]
local function installSync()
    local handlers = {}

    function handlers.tourniquetState(args)
        if type(args) ~= "table" or not args.online then return end

        local patient = getPlayerByOnlineID(args.online)
        if not patient then return end

        BQoL.Tourniquet.replaceAll(patient, args.parts)
    end

    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= BQoL.COMMAND_MODULE then return end

        local handler = handlers[command]
        if not handler then return end

        -- One bad packet must not take down the client's event handler.
        local ok, err = pcall(handler, args)
        if not ok then
            BQoL.warn("server command %q failed: %s", tostring(command), tostring(err))
        end
    end)

    --[[
        The pushes above only fire when the state changes, so a doctor who
        opens a patient's panel long after the limb was tied off has never been
        told. setOtherPlayer is where the panel learns it is treating someone
        else, so that is where to ask.
    ]]
    local originalSetOtherPlayer = ISHealthPanel.setOtherPlayer

    function ISHealthPanel:setOtherPlayer(playerObj)
        originalSetOtherPlayer(self, playerObj)

        -- self.character is the patient here; otherPlayer is the doctor.
        local patient = self:getPatient()
        if isClient() and patient and playerObj and patient ~= playerObj then
            sendClientCommand(playerObj, BQoL.COMMAND_MODULE, "tourniquetRequest",
                { online = patient:getOnlineID() })
        end
    end
end

--[[
    Reconciles records against worn items at load, so the "- Tourniquet" line
    and the removal option are right from the moment the panel opens rather
    than only after a right-click -- and so a save carrying a phantom record
    from the duplicate-migration bug heals itself without the player having to
    find the limb first.

    OnCreatePlayer has already fired for whoever just loaded in by the time
    features initialise, so they are reconciled directly; the handler is for
    splitscreen players joining afterwards.
]]
local function installReconcile()
    local function reconcile(playerObj)
        if not playerObj then return end
        local _, orphans = BQoL.Tourniquet.reconcile(playerObj)
        resolveOrphans(playerObj, orphans)
    end

    for i = 0, getNumActivePlayers() - 1 do
        reconcile(getSpecificPlayer(i))
    end

    Events.OnCreatePlayer.Add(function(_, playerObj)
        reconcile(playerObj)
    end)
end

--[[
    Watches for the leg item coming off by any route.

    ISUnequipAction fires OnClothingUpdated on both of its paths
    (ISUnequipAction.lua:97 and :132), as do ISClothingExtraAction and
    ISEquipWeaponAction, so one listener covers every way an item can leave the
    body without wrapping any of them.

    The work is deferred a tick because this fires from the middle of
    ISUnequipAction:complete, which goes on using self.item afterwards -- and
    untying destroys that item. Self-removing one-shot handler, the same shape
    vanilla uses at ISCampingMenu.lua:447-455.

    The re-entrancy flag covers unwearLeg, which fires this same event itself
    on its way to clearing the record: without it, every untie would queue
    another round of work for a limb that is already being dealt with. It is
    cleared inside afterTick, after a BQoL.safe that cannot raise, so a bad
    reconcile cannot leave the listener switched off for the session.
]]
local function installUnequip()
    local resolving = false

    local function afterTick(fn)
        local handler
        handler = function()
            Events.OnTick.Remove(handler)
            BQoL.safe("Tourniquet.afterTick", fn)
            resolving = false
        end
        Events.OnTick.Add(handler)
    end

    Events.OnClothingUpdated.Add(function(character)
        if resolving or not character then return end

        local _, orphans = BQoL.Tourniquet.reconcile(character)
        if not orphans then return end

        resolving = true
        afterTick(function()
            resolveOrphans(character, orphans)
        end)
    end)
end

local function install()
    installMenu()
    installPanel()
    installSync()
    installReconcile()
    installUnequip()
end

BQoL.feature{
    id = "Tourniquet",
    sandbox = "TourniquetEnabled",
    init = install,
}
