if getCore():isDedicated() then return; end
require "ISUI/ISPostDeathUI"

function ISPostDeathUI:getKillCountLine(player)
    local weaponKill = player:getZombieKills();--B42.12: now includes car kills (most of) and explosion kills
    local fireKill = 0;
    local md = player:getModData().AKCModData
    if md then
        fireKill = (md.fk or 0);
    end
    local totalKill = weaponKill + fireKill;
    if totalKill ~= 1 then
        return getText("IGUI_Gametime_zombiesCount", totalKill)
    else
        return getText("IGUI_Gametime_zombieCount", totalKill)
    end
end

local upperlayer = {}
upperlayer.ISPostDeathUI = {}
upperlayer.ISPostDeathUI.addToUIManager = ISPostDeathUI.addToUIManager
upperlayer.ISPanelJoypad = {}
upperlayer.ISPanelJoypad.addToUIManager = ISPanelJoypad.addToUIManager
upperlayer.ISUIElement = {}
upperlayer.ISUIElement.addToUIManager = ISUIElement.addToUIManager
function ISPostDeathUI:addToUIManager()
    if SandboxVars and SandboxVars.KillCount and SandboxVars.KillCount.includePostDeathUI then
        local playerObj = getSpecificPlayer(self.playerIndex)
        local vanillakillsLine = getGameTime():getZombieKilledText(playerObj)
        local killLineIter = nil
        for i=0, #self.lines do
            if vanillakillsLine == self.lines[i] then killLineIter = i end
        end
        
        --replace the nb kills line
        if killLineIter ~= nil then self.lines[killLineIter] = self:getKillCountLine(playerObj) end
    end
    
    --3 potential upper layers for the real addToUIManager
    if upperlayer.ISPostDeathUI.addToUIManager then
        upperlayer.ISPostDeathUI.addToUIManager(self);
    elseif upperlayer.ISPanelJoypad.addToUIManager then
        upperlayer.ISPanelJoypad.addToUIManager(self);
    elseif upperlayer.ISUIElement.addToUIManager then
        upperlayer.ISUIElement.addToUIManager(self);
    end
end
