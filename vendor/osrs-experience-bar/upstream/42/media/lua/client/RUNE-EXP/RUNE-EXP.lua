barHandle = nil;

function onCreatePlayer(idx, player)
	if barHandle == nil then
		barHandle = ISExpBar:new(idx, player);
		barHandle:initialize();
		barHandle:instantiate();
		barHandle:addToUIManager();
		barHandle:addDropdownPanel();
		barHandle:initConfig();
		barHandle:addConfigPanel();
	elseif barHandle:getPlayerIsDead() == true then
		barHandle:setPlayer(idx, player);
	end
end

function onPlayerDeath(player)
	if barHandle ~= nil and player == barHandle:getPlayer() then
		barHandle:setPlayerIsDead(true);
	end
end

function onAddExp(player, perk, amount)
	if perk ~= nil and barHandle ~= nil and player == barHandle:getPlayer() then
		barHandle:expDrop(perk, amount);
	end
end

local function OnSave()
	if barHandle ~= nil then
		barHandle:writeConfig();
	end
end

Events.OnCreatePlayer.Add(onCreatePlayer);
Events.OnPlayerDeath.Add(onPlayerDeath);
Events.AddXP.Add(onAddExp);
Events.OnSave.Add(OnSave);