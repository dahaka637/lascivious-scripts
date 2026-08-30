

KCShared = {}
KCShared.Verbose = false
KCShared.Key = 'KillCount'


function KCShared.getModData()
    if isServer() then
        return ModData.getOrCreate(KCShared.Key)
    else
        return ModData.get(KCShared.Key)
    end
end