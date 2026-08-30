--[[
    Burris Quality of Life -- appending to the health panel's body-part menu.

    ISHealthPanel:doBodyPartContextMenu is file-local, so the only way to add an
    entry is to let the original build its menu and append afterwards through
    getPlayerContextMenu(). ISContextMenu.get() cannot be used for that: it
    CLEARS the menu (ISContextMenu.lua:1166).

    The trap that made this file necessary is the last thing the original does
    (ISHealthPanel.lua:1873):

        if self.blockingMessage or context:isEmpty() then
            context:setVisible(false);
        end

    A limb vanilla has nothing to offer for gets its menu hidden BEFORE the
    append happens, so the option lands on an invisible menu and right-clicking
    the limb appears to do nothing at all. That is not an edge case for the
    tourniquet feature, it is its end state: bleeding is cut, the wound heals,
    the added pain decays back under vanilla's `getAdditionalPain() > 10`
    threshold, and the limb is then listed only because of the getDamagedParts
    patch in BQoL_Tourniquet -- with every vanilla handler silent. The
    tourniquet became permanent and the player was told nothing.

    reveal() undoes that hide, and only that hide: blockingMessage is vanilla's
    other reason to hide the menu and is left alone.
]]

require "BQoL/BQoL_Core"

BQoL.HealthMenu = BQoL.HealthMenu or {}

local HealthMenu = BQoL.HealthMenu

--[[
    The live menu the original doBodyPartContextMenu just filled, plus the
    player number it belongs to.

    Same doctor/patient split the panel itself uses (ISHealthPanel.lua:1797):
    otherPlayer is the doctor when treating someone else, and the menu belongs
    to whoever is doing the treating.
]]
function HealthMenu.get(panel)
    if not panel then return nil, nil end

    local owner = panel.otherPlayer or panel.character
    if not owner then return nil, nil end

    local ok, playerNum = BQoL.tryCall(owner, { "getPlayerNum" })
    if not ok or not playerNum then return nil, nil end

    return getPlayerContextMenu(playerNum), playerNum
end

--[[
    Shows a menu the original hid for being empty. Call after adding options.

    ISContextMenu:addOption already recalculates height and width
    (ISContextMenu.lua:883-885), and vanilla hides with a bare setVisible(false)
    rather than hideSelf(), so forceVisible/visibleCheck are still as
    ISContextMenu.get left them. Visibility really is the only thing to put
    back.

    Returns true when it actually revealed something, for the tests.
]]
function HealthMenu.reveal(panel, context, playerNum)
    if not panel or not context then return false end

    -- Vanilla's other reason for hiding: the patient cannot be treated right
    -- now (too far away, and so on). That one stands.
    if panel.blockingMessage then return false end

    if context:getIsVisible() then return false end

    context:setVisible(true)
    context:bringToTop()

    --[[
        Vanilla hands the joypad its focus only for a menu that survived the
        hide (ISHealthPanel.lua:1877-1882), so a menu revealed here has to be
        handed over the same way or a controller player sees it and cannot move
        onto it.
    ]]
    if playerNum and JoypadState and JoypadState.players
        and JoypadState.players[playerNum + 1] then
        context.mouseOver = 1
        context.origin = panel
        JoypadState.players[playerNum + 1].focus = context
        updateJoypadFocus(JoypadState.players[playerNum + 1])
    end

    return true
end
