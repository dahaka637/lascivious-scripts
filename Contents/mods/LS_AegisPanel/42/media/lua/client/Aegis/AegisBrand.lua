-- Client state of the server branding: operators may rename the panel
-- heads, both windows read AegisBrand.title().
require "Aegis/AegisTheme"

AegisBrand = AegisBrand or {}
-- nil = no custom name, the heads fall back to AEGIS
AegisBrand.name = nil

function AegisBrand.title()
    local n = AegisBrand.name
    if type(n) == "string" and n ~= "" then return n end
    return "AEGIS"
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE or command ~= "brandSync" then return end
    local n = args and args.name
    AegisBrand.name = (type(n) == "string" and n ~= "") and n or nil
end)

-- ask right at game start (rightsReq pattern) instead of on the first
-- window open: a head opened later would flash AEGIS first, and clients
-- that never open a panel still see the mini bars and toasts. Unlike
-- rightsReq this is NOT admin gated, the blue head shows the brand too.
-- In solo the in-process server part answers over the same event.
Events.OnGameStart.Add(function()
    AegisBrand.name = nil
    local p = getPlayer()
    if p then
        sendClientCommand(p, AegisShared.MODULE, "brandReq", {})
    end
end)
