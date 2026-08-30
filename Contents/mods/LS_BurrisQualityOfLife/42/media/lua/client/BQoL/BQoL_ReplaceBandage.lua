--[[
    Burris Quality of Life -- "Replace Bandage" on a dirty bandage.

    Vanilla makes you remove the dirty bandage and then apply a fresh one as
    two separate clicks. The health panel's handlers (HRemoveBandage,
    HApplyBandage) are file-local and unreachable, so this wraps
    ISHealthPanel:doBodyPartContextMenu and appends the entry after the
    original menu is built.

    Three traps, all verified against 42.20:

      - ISContextMenu.get() CLEARS the menu (ISContextMenu.lua:1166), so the
        option must be added through getPlayerContextMenu(), which returns the
        live menu the original call just filled. BQoL_HealthMenu owns that
        lookup, and the reveal that goes with it: the original hides a menu it
        found empty before an appended option can make it non-empty.

      - Dirtiness is a flag, not a type: bodyPart:getBandageType() keeps
        returning the clean item type ("Base.Bandage") while
        bodyPart:isBandageDirty() tracks the grime.

      - The replacement bandage may not be picked at click time. ISApplyBandage
        is mirrored to the server, which rebuilds it from serialised arguments
        and cannot resolve an item that moved in the meantime -- and a two
        minute removal action is plenty of time for that. Vanilla's answer is
        HealthPanelAction, a client-only trampoline whose perform() runs at
        execution time and only then builds the real action; BQoL_BandageLogic
        supplies the handler half. Queueing a second ISApplyBandage directly
        here worked in single player and threw
        "NetTimedAction.perform> Exception thrown" on every dedicated server.
]]

require "BQoL/BQoL_Core"
require "BQoL/BQoL_HealthMenu"
require "BQoL/BQoL_BandageLogic"

local function onReplaceSelected(target, doctor, patient, bodyPart)
    -- Cheap early-out; the handler re-checks at the moment it matters.
    if not BQoL.Bandage.findReplacement(doctor, bodyPart) then return end

    -- Mirrors HRemoveBandage.perform, then defers the apply half exactly the
    -- way a second click on vanilla's own Bandage entry would.
    ISTimedActionQueue.add(ISApplyBandage:new(doctor, patient, nil, bodyPart, false))
    ISTimedActionQueue.add(HealthPanelAction:new(
        doctor, BQoL.Bandage.newApplyHandler(doctor, patient, bodyPart)))
end

local function install()
    local original = ISHealthPanel.doBodyPartContextMenu

    function ISHealthPanel:doBodyPartContextMenu(bodyPart, x, y)
        original(self, bodyPart, x, y)

        if not bodyPart:bandaged() or not bodyPart:isBandageDirty() then return end

        -- Same doctor/patient assignment as BaseHandler (ISHealthPanel.lua:1137).
        local doctor = self.otherPlayer or self.character
        local patient = self.character
        if not doctor or not patient then return end

        if not BQoL.Bandage.findReplacement(doctor, bodyPart) then return end

        local context, playerNum = BQoL.HealthMenu.get(self)
        if not context then return end

        context:addOption(getText("ContextMenu_BQoL_ReplaceBandage"),
            nil, onReplaceSelected, doctor, patient, bodyPart)

        -- A dirty bandage always gives vanilla its own Remove Bandage entry to
        -- show, so the menu is never empty here in practice. Revealed anyway
        -- rather than relying on that: it is a vanilla implementation detail,
        -- not a guarantee.
        BQoL.HealthMenu.reveal(self, context, playerNum)
    end
end

BQoL.feature{
    id = "ReplaceBandage",
    sandbox = "ReplaceBandageEnabled",
    init = install,
}
