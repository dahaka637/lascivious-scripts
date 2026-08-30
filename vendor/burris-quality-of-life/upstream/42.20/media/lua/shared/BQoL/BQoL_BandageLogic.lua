--[[
    Burris Quality of Life -- bandage replacement rules.

    Split out of BQoL_ReplaceBandage.lua so the decisions here can be tested
    outside the game (tools/test/replace_bandage.lua), the same reason
    BQoL_PryLogic and BQoL_TourniquetLogic exist. Only the client menu calls
    it, but everything it touches (ISApplyBandage, ISTimedActionQueue,
    ISInventoryTransferUtil) lives in the shared tree, so it sits alongside its
    two siblings rather than being the odd one out in client/.

    The handler this file builds is the important part. ISApplyBandage defines
    complete(), which is what makes LuaTimedActionNew mirror it to the server
    (useCustomRemoteTimedActionSync is set only when the class has no
    complete), and the server rebuilds the action from arguments serialised by
    the parameter names of ISApplyBandage:new. An InventoryItem crosses as
    container + id and resolves through ItemContainer.getItemWithID, which
    yields nil when the item is no longer where the client said it was --
    whereupon the server's complete() dereferences a nil self.item and the
    whole action dies inside NetTimedAction.perform.

    So the item handed to ISApplyBandage must be found immediately before the
    action runs, never held across another action. Vanilla enforces this by
    routing every health-panel entry through HealthPanelAction, whose perform()
    runs at execution time and only then constructs the real action
    (ISHealthPanel.lua:982 and HApplyBandage:perform, line 1187).
    HealthPanelAction has no complete() of its own, so it never goes over the
    wire. newApplyHandler below is the handler half of that arrangement.
]]

require "BQoL/BQoL_Core"

BQoL = BQoL or {}
BQoL.Bandage = BQoL.Bandage or {}

local Bandage = BQoL.Bandage

--[[
    Picks what to bandage with: the same type as the applied bandage if one is
    carried, otherwise anything with bandage power -- the same acceptance rule
    as vanilla's own Apply menu (ISHealthPanel.lua:1153).
]]
function Bandage.findReplacement(doctor, bodyPart)
    if not doctor or not bodyPart then return nil end

    local inventory = doctor:getInventory()
    if not inventory then return nil end

    local wanted = bodyPart:getBandageType()
    local items = inventory:getAllEvalRecurse(
        function(item) return item:getBandagePower() > 0 end)

    local fallback = nil
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if wanted and item:getFullType() == wanted then
            return item
        end
        fallback = fallback or item
    end
    return fallback
end

--[[
    Builds the handler HealthPanelAction drives. Queue one of these after the
    removal action and the fresh bandage is chosen, fetched and applied only
    once the dirty one is actually off.
]]
function Bandage.newApplyHandler(doctor, patient, bodyPart)
    local handler = {}

    --[[
        HealthPanelAction:isValid treats any non-nil return as valid
        (ISHealthPanel.lua:984). Returning false here just drops the second
        half of the replacement: the removal has already happened and stands.

        Deliberately does NOT check bodyPart:bandaged(), the way vanilla's
        HApplyBandage:isValid does via isInjured(). Vanilla can, because a
        human opens the menu again between the two clicks. We cannot:
        IsoGameCharacter's action loop runs perform() -- which starts the next
        queued action -- before complete(), and on a multiplayer client it
        skips the Lua complete() entirely, leaving the body part to be updated
        by the server's syncBodyPart whenever it arrives. The part therefore
        still reads as bandaged when this runs, and gating on it would drop
        every replacement.
    ]]
    function handler:isValid()
        return Bandage.findReplacement(doctor, bodyPart) ~= nil
    end

    -- Mirrors BaseHandler:toPlayerInventory (ISHealthPanel.lua:1125) followed
    -- by HApplyBandage:perform (line 1187). addAfter, not
    -- ISTimedActionQueue.add: add appends to the tail of the queue, which
    -- would run the transfer after the bandaging instead of before it.
    function handler:perform(previousAction)
        local item = Bandage.findReplacement(doctor, bodyPart)
        if not item then return end

        if item:getContainer() ~= doctor:getInventory() then
            local transfer = ISInventoryTransferUtil.newInventoryTransferAction(
                doctor, item, item:getContainer(), doctor:getInventory())
            ISTimedActionQueue.addAfter(previousAction, transfer)
            previousAction = transfer
        end

        ISTimedActionQueue.addAfter(previousAction,
            ISApplyBandage:new(doctor, patient, item, bodyPart, true))
    end

    return handler
end
