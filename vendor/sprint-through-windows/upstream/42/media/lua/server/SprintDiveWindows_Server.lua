local function onClientCommand(module, command, player, args)
    if module ~= "SprintDiveWindows" then return end
    if not player then return end

    if command == "glassCut" then
        local bodyDamage = player:getBodyDamage()
        if not bodyDamage then return end

        bodyDamage:setScratchedWindow()
        return
    end

    if command == "diveOutcome" then
        if not args or not args.id or not args.outcome then return end
        if args.outcome ~= "fall" and args.outcome ~= "success" then return end

        sendServerCommand("SprintDiveWindows", "diveOutcome", {
            id = args.id,
            outcome = args.outcome,
            dive = (args.dive == true),
        })
        return
    end

    if command == "diveLanding" then
        if not args or not args.id or not args.x or not args.y then return end

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
