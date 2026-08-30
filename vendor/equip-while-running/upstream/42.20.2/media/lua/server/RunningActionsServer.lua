local function OnClientCommand(module, command, player, args)
    if module == "RunningActionsMod" and command == "SyncAnimVar" then
        -- Relay the animation state packet to all connected clients
        sendServerCommand("RunningActionsMod", "SyncAnimVar", args)
    end
end

Events.OnClientCommand.Add(OnClientCommand)