local function onClientCommand(module, command, player, args)
    if module ~= "SprintDiveWindows" then return end
    if not player then return end

    if command == "glassCut" then
        local bodyDamage = player:getBodyDamage()
        if not bodyDamage then return end

        bodyDamage:setScratchedWindow()
        return
    end

    -- Only relay a client's report about its own character -- upstream trusted
    -- args.id as-is, letting any client set another player's ClimbFenceOutcome/
    -- DiveThruWindow anim state, or reposition another player's rendered X/Y/Z on
    -- every other connected client, by spoofing args.id (see LS-001 in
    -- vendor/sprint-through-windows/LOCAL_CHANGES.md).
    if command == "diveOutcome" then
        if not args or args.id ~= player:getOnlineID() or not args.outcome then return end
        if args.outcome ~= "fall" and args.outcome ~= "success" then return end

        sendServerCommand("SprintDiveWindows", "diveOutcome", {
            id = args.id,
            outcome = args.outcome,
            dive = (args.dive == true),
        })
        return
    end

    if command == "diveLanding" then
        if not args or args.id ~= player:getOnlineID() or not args.x or not args.y then return end

        sendServerCommand("SprintDiveWindows", "diveLanding", {
            id = args.id,
            x = args.x,
            y = args.y,
            z = args.z or 0,
        })
        return
    end
end

Events.OnClientCommand.Add(onClientCommand)
