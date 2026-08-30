
--solo and host do not need to update they got direct access to server gmd
if not isClient() then return end

--receive the whole global mod data client side
require 'KillCountShared'

---subscribe to MD
function KCShared.initGMD()
    ModData.request(KCShared.Key);
end

--- merge subscribed global mod data
function KCShared.OnReceiveGlobalModData(_module, _packet)
    if _module == KCShared.Key then
        if _packet then
            if KCShared.Verbose then print("Client receives Global mod data update "..tab2str(_module)..' '..tab2str(_packet)) end
            ModData.add(_module, _packet)
            ISCharacterKills.instance:onPlayersKillsUpdate();
        else
            if KCShared.Verbose then print("Client receives Global mod data synchro "..tab2str(_module)..' '..tab2str(_packet)) end
        end
    end
end

--- install callbacks
--register the database update callback
Events.OnInitGlobalModData.Add(KCShared.initGMD)
--set on database update
Events.OnReceiveGlobalModData.Add(KCShared.OnReceiveGlobalModData)
