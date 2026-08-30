
require 'KillCountUpdate'

if getCore():isDedicated() then
    if KillCount.Verbose then print ('KillCountExports Dedicated Stop export.') end
    return;
end

if KillCount.Verbose then print ('KillCountExports export loading.') end
function KillCount.doExport()
    return SandboxVars.KillCount and SandboxVars.KillCount.doExport
end


--This part is inspired by TwitchStats mod
local lastExportedKillNumber = nil
function KillCount.updateExportFile(player)
    if not player or not KillCount.doExport() then return end
    if not player == getPlayer() then return end
    if not player:hasModData() then return end
    
    local totalKill  = player:getZombieKills();
    local md = player:getModData().AKCModData ;
    if md then
        local fireKill = (md.fk or 0) + (md.ek or 0);
        local carKill = (md.ck or 0);
        totalKill = totalKill + fireKill + carKill;
    end
    
    if totalKill ~= lastExportedKillNumber then
        local kcfile = getFileWriter("killcount.txt", true, false);
        if kcfile then
            lastExportedKillNumber = totalKill
            kcfile:write(tostring(totalKill));
            kcfile:close();
            if KillCount.Verbose then print ('KillCount.updateExportFile '..totalKill) end
        end
    end
end

Events.OnPlayerUpdate.Add(KillCount.updateExportFile)