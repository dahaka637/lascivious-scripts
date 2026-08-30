--[[
    Burris Quality of Life -- keeps a belted flashlight belted across a reload.

    This is the third distinct failure of the tool-loop tweak. 9d99589 moved the
    script patch to shared/ so multiplayer saw it at all; 0529d41 added the
    retrofit for flashlights that already existed. Both were necessary, and
    both are what make this one visible: the torch now attaches, and then falls
    off every time the save or the server is reloaded.

    The chain, traced through 42.20:

      1. attachmentType is a field on InventoryItem, copied from the script item
         at construction and never re-read (see BQoL_ItemParams). The player's
         inventory is deserialised BEFORE OnGameStart, which is when the
         DoParam runs -- so on every load the carried torch is rebuilt with
         attachmentType = nil.

      2. ISHotbar:update() (ISHotbar.lua:248-253) polices its slots every single
         frame:

             if not slot or not self:canBeAttached(slot, item) ...
                 then self:removeItem(item, false)

         canBeAttached (:290-308) matches item:getAttachmentType() against the
         slot definition, so a nil type fails it.

      3. removeItem (:325-336) then clears attachedSlot, attachedSlotType and
         attachedToModel. attachedSlot is the saved field that would have put
         the torch back on the belt -- once it is -1 there is nothing left to
         restore, and the next save writes the torch out as unattached. The
         loss is permanent, not cosmetic.

    The retrofit sweep in BQoL_ItemParams cannot win this. It waits on
    OnPlayerUpdate for a non-empty inventory, and its own comment records why:
    on a multiplayer client the carried inventory arrives after the first
    OnPlayerUpdate. One frame of ISHotbar:update() in the meantime is enough,
    and by the time the sweep sets attachmentType the attachment it was meant
    to preserve has already been discarded.

    So do not race it. canBeAttached is the exact predicate that decides to
    strip the item, and it is asked before removeItem is called -- answering it
    correctly, and fixing the item while we are there, lands ahead of the strip
    on the first frame no matter what order the events fired in.

    Three things fall out of patching here rather than earlier:

      - Manual attachment goes through the same predicate (ISHotbar.lua:637 and
        the hotbar radial menu), so a torch looted from a container built before
        the script patch can be belted too.
      - Both re-attach paths resolve their model with
        slotDef.attachments[item:getAttachmentType()] (:258 and :541), where a
        nil type silently yields a nil slot. Setting the type feeds both.
      - Nothing is touched when the sandbox option is off: the registry skips
        init entirely, so the wrap is never installed.

    ISHotbar is client-only, which is why this half lives here while the list
    and the script patch stay in shared/ -- the same split, for the same
    reason, as the multiplayer fix in 9d99589.
]]

require "BQoL/BQoL_Core"

local function install()
    local original = ISHotbar.canBeAttached

    if type(original) ~= "function" then
        BQoL.warn("FlashlightSlot: ISHotbar.canBeAttached is missing; " ..
            "belted flashlights will not survive a reload")
        return
    end

    --[[
        Checked before the wrap goes in, not inside it. The wrap runs from
        ISHotbar's per-frame policing loop, so a nil here would not be one
        error -- it would be one error per frame for the rest of the session.
    ]]
    if not BQoL.has(BQoL.ItemParams, "retrofit") then
        BQoL.warn("FlashlightSlot: BQoL_ItemParams did not load; " ..
            "leaving ISHotbar alone")
        return
    end

    function ISHotbar:canBeAttached(slot, item)
        if original(self, slot, item) then return true end

        --[[
            Only ever a second chance, never a first: anything vanilla already
            accepted took the branch above, so this is reached only for an item
            the slot has just refused. retrofit itself is what narrows it -- it
            answers false for everything except the two flashlight types this
            feature owns, and false again for one already carrying the type, so
            the per-frame caller writes at most once per item.
        ]]
        if not BQoL.ItemParams.retrofit(item) then return false end

        BQoL.log("FlashlightSlot: retrofitted %s at attach time",
            tostring(item:getFullType()))

        return original(self, slot, item)
    end
end

BQoL.feature{
    id = "FlashlightSlot",
    sandbox = "TweakFlashlightSlot",
    init = install,
}
