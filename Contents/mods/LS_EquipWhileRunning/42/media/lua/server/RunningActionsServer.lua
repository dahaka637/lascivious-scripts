local function OnClientCommand(module, command, player, args)
    if module == "RunningActionsMod" and command == "SyncAnimVar" then
        -- Only relay a client's report about its own character -- upstream trusted
        -- args.id as-is, letting any client set arbitrary anim variables on any other
        -- player's Character by spoofing args.id/args.var/args.val (see LS-001 in
        -- vendor/equip-while-running/LOCAL_CHANGES.md).
        if not args or args.id ~= player:getOnlineID() then return end
        sendServerCommand("RunningActionsMod", "SyncAnimVar", args)
    end
end

Events.OnClientCommand.Add(OnClientCommand)