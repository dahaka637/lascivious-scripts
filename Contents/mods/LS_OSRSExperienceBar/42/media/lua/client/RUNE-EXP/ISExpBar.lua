ISExpBar = ISPanel:derive("ISExpBar");

function ISExpBar:new(playerIndex, player)
	-- Core
	local fontSize, fontHeightMed;
    fontSize = getCore():getOptionFontSize();
    fontHeightMedium = getTextManager():getFontHeight(UIFont.Medium);

	local bw, bh;
	-- bw = 140;
	-- bh = 38;
	bw = 140 + (15 * (fontSize-1));
	bh = 18 + fontHeightMedium;

	local barHandle = {};
	barHandle = ISPanel:new(getCore():getScreenWidth()-400, 200, bw, bh);
	setmetatable(barHandle, self);
    self.__index = self;



	barHandle.playerIndex = playerIndex;
	barHandle.player = player;
	barHandle.player_isDead = false;

	-- The AddXP event is not triggered on multiplayer clients, so there we watch
	-- the player's exp values for changes instead of waiting to be told about them.
	barHandle.xpPoll = isClient();
	barHandle.xpSnapshot = {};
	barHandle.colour = {r=0,g=1,b=0};
	barHandle.baseWidth = bw;
	barHandle.baseHeight = bh;

	barHandle.moveWithMouse = true;
	barHandle:setCapture(false);

	barHandle.backgroundColor = 	{r=0.22, g=0.19, b=0.14, a=0.5};
	barHandle.borderColor = 		{r=0.22, g=0.19, b=0.14, a=1.0};
	barHandle.borderColor_inner = 	{r=0.35, g=0.32, b=0.27, a=1.0};

	barHandle.colour_black = 		{r=0.0, g=0.0, b=0.0, a=1.0};

	-- Actual experience bar
	barHandle.bar_w = barHandle.width - 2;
	barHandle.bar_h = 10 + (1 * (fontSize-1));

	barHandle.bar_x = 1;
	barHandle.bar_y = barHandle.height - barHandle.bar_h - 1;

	-- Tooltip
	barHandle.tooltip_visible = false;
	barHandle.tooltip_text_offset_x = 3;
	barHandle.tooltip_text_offset_y = 1;
	barHandle.tooltip_x = -20;
	barHandle.tooltip_y = barHandle.height + 5;
	barHandle.tooltip_w = barHandle.width + 40 + (25 * (fontSize-1));
	barHandle.tooltip_h = (barHandle.tooltip_text_offset_y * 2) + (getTextManager():getFontHeight(UIFont.Small) * 6);
	barHandle.tooltip_colour = {r=1.0, g=0.98, b=0.61};

	-- Special text position adjustments for specific languages
	barHandle.bar_translationOffset_y = 0; -- medium font

	local translationLanguage;
	translationLanguage = tostring(Translator.getLanguage());

	--print("ISExpBar(): translationLanguage: ", translationLanguage)

	if translationLanguage == "RU" then
		-- Russian
		barHandle.bar_translationOffset_y = 2;
	elseif translationLanguage == "KO" then
		-- Korean
		barHandle.bar_translationOffset_y = 2;
	elseif translationLanguage == "CH" then
		-- Traditional Chinese
		barHandle.bar_translationOffset_y = 3;
		barHandle.tooltip_text_offset_y = barHandle.tooltip_text_offset_y + 1;
		barHandle.tooltip_h = barHandle.tooltip_h + 1;
	end

	-- Hidden XP button
	barHandle.button_mode = false;
	barHandle.button_sprite = getTexture("media/ui/RUNE-EXP_XpButton.png");
	barHandle.button_w = 27;
	barHandle.button_h = 27;
	barHandle.button_offset_x = bw - barHandle.button_w;
	barHandle.button_offset_y = 0;

	-- Skill and skill icons
	barHandle.icon_x = 4;
	--barHandle.icon_y = 2;
	barHandle.icon_wh = 25;

	barHandle.icon_y = math.max(2, math.floor( ((barHandle.bar_y) * .5) - (barHandle.icon_wh * .5) ));
	barHandle.icon_text_y = 2 - (1 * fontSize);
	barHandle.icon_drop_y_offset = 3 * (fontSize-1);

	barHandle.sprites = {};
	barHandle.perkIndices = {};
	barHandle.conf_trackSkill = {};
	barHandle:loadSprite("Unknown");

	barHandle.skill_current = ""; -- perk type
	barHandle.skill_current_displayName = ""; -- perk name
	barHandle.sprite = nil;
	
	barHandle.skill_expTable = {};

	for i=1,Perks.getMaxIndex() do
		local perk, perkType;
		perk = PerkFactory.getPerk(Perks.fromIndex(i - 1));
		if perk and perk:getParent() ~= Perks.None then
			--perkName = perk:getName();
			perkType = tostring(perk:getType());
			barHandle:loadSprite(perkType);
			barHandle.perkIndices[perkType] = i - 1;

			barHandle.skill_expTable[perkType] = {
				tonumber(perk:getXp1()), tonumber(perk:getXp2()), tonumber(perk:getXp3()), tonumber(perk:getXp4()), tonumber(perk:getXp5()),
				tonumber(perk:getXp6()), tonumber(perk:getXp7()), tonumber(perk:getXp8()), tonumber(perk:getXp9()), tonumber(perk:getXp10()),
			};

			barHandle:setTrackSkill(perkType, (perkType ~="Fitness") and (perkType ~="Strength")  and (perkType ~="Lightfoot") and (perkType ~="Sneak") and (perkType ~="Maintenance"));
		end
	end
	
	--barHandle:setSkill("Carpentry");
	barHandle:setSkill("Woodwork");

	barHandle.skill_roundedExp = {["Lightfoot"] = 0, ["Sneak"] = 1}; -- Round up exp for these skills, only show exp drops at least 1.0 full exp has been gained

	-- Total exp amount required for each level (there's probably a better way to retreive this?)
	--barHandle.expTable_normal = 	{75, 150, 300, 750, 1500, 3000, 4500, 6000, 7500, 9000};
	--barHandle.expTable_passive = 	{1500, 3000, 6000, 9000, 18000, 30000, 60000, 90000, 120000, 150000};

	-- The order the skills appear in the in-game menu (there's probably a better way to retreive this?)
	barHandle.skill_order = {
		[1] = "Fitness", [2] = "Strength", [3] = "Sprinting", [4] = "Lightfoot", [5] = "Nimble",
		[6] = "Sneak", [7] = "Axe", [8] = "Blunt", [9] = "SmallBlunt", [10] = "LongBlade",
		[11] = "SmallBlade", [12] = "Spear", [13] = "Maintenance", [14] = "Woodwork", [15] = "Carving",
		[16] = "Masonry", [17] = "Pottery", [18] = "Glassmaking", [19] = "FlintKnapping", [20] = "Blacksmith",
		[21] = "Cooking", [22] = "Farming", [23] = "Husbandry", [24] = "Butchering", [25] = "Doctor",
		[26] = "Electricity", [27] = "MetalWelding", [28] = "Mechanics", [29] = "Tailoring", [30] = "Aiming",
		[31] = "Reloading", [32] = "Fishing", [33] = "Trapping", [34] = "PlantScavenging", [35] = "Tracking"
	};


	-- Adjust the size of the tooltip window based on the longest skill name
	barHandle.longestNameWidth = 0;
	local nameWidth;
	for skill_type in pairs(barHandle.conf_trackSkill) do
		nameWidth = getTextManager():MeasureStringX(UIFont.Small, barHandle:getPerkNameFromType(skill_type));
		if nameWidth > barHandle.longestNameWidth then
			barHandle.longestNameWidth = nameWidth;
		end
	end

	barHandle.tooltip_w = math.max(barHandle.tooltip_w, barHandle.longestNameWidth + 80 + (20 * (fontSize-1)));
	barHandle.tooltip_x = -math.floor((barHandle.tooltip_w - barHandle.width) * .5);

	-- Exp drops
	barHandle.drop_distance = 100; -- Vertical distance from the xp bar that the xp drops will initially appear
	barHandle.drop_sep_min = 12;
	barHandle.drop_sep_set = 20;
	barHandle.drop_distance_limit = barHandle.drop_sep_set * 3;
	barHandle.drop_x = barHandle.width - 80;
	barHandle.expDrops = {};

	-- Exp drop indexing
	barHandle.expDrop_skillType = 0;
	barHandle.expDrop_skillDisplayName = 1;
	barHandle.expDrop_expAmount = 2;
	barHandle.expDrop_alpha = 3;
	barHandle.expDrop_offset = 4;
	barHandle.expDrop_varCount = 5;

	-- Exp drop queue
	barHandle.dropQueue = {};
	barHandle.queue_skillType = 0;
	barHandle.queue_expAmount = 1;
	barHandle.queue_perk = 2
	barHandle.queue_varCount = 3;

	-- Other panel instances
	barHandle.dropdownPanel = nil;
	barHandle.configPanel = nil;

	barHandle.CONFIG_VERSION = 3;

	return barHandle;
end

function ISExpBar:initialize()
	ISUIElement.initialise(self);
end

--Override
function ISExpBar:onRightMouseDown(x, y)
	if not self:dropdownPanelIsOpen() then
		self.dropdownPanel:setOpen(true, self:getX() + x - 20, self:getY() + y - 5);
		self.tooltip_visible = false;
	end
end

--Override
function ISExpBar:onMouseMove(dx, dy)
	self.tooltip_visible = true;

	ISPanel.onMouseMove(self, dx, dy); --Super
end

--Override
function ISExpBar:onMouseMoveOutside(dx, dy) 
	self.tooltip_visible = false;

	ISPanel.onMouseMoveOutside(self, dx, dy); --Super
end

function ISExpBar:getPlayer()
	return self.player;
end

function ISExpBar:setPlayer(playerIndex, player)
	self.playerIndex = playerIndex;
	self.player = player;
	self.xpSnapshot = {};
	self:setPlayerIsDead(false);
end

function ISExpBar:pollXpChanges()
	-- Compare each skill's exp against the last seen value and raise a drop for
	-- any gain. Used on multiplayer clients, where AddXP never fires.
	local xpHandler, perk, xp, xpPrev, getMasteryExp;

	if self.player == nil then
		return;
	end

	xpHandler = self.player:getXp();
	if xpHandler == nil then
		return;
	end

	getMasteryExp = self:getMasteryExpReader();

	for skill_type, perkIndex in pairs(self.perkIndices) do
		perk = PerkFactory.getPerk(Perks.fromIndex(perkIndex));
		if perk ~= nil then
			xp = xpHandler:getXP(perk);
			if getMasteryExp ~= nil then
				xp = xp + getMasteryExp(self.player, perk);
			end
			xpPrev = self.xpSnapshot[skill_type];
			self.xpSnapshot[skill_type] = xp;

			-- A nil previous value just seeds the snapshot; a lower one means the
			-- exp was reset (death, debug menu) and is not a gain.
			if xpPrev ~= nil and xp > xpPrev then
				self:expDrop(perk, xp - xpPrev);
			end
		end
	end
end

function ISExpBar:getPlayerIsDead()
	return self.player_isDead;
end

function ISExpBar:setPlayerIsDead(isDead)
	self.player_isDead = isDead;
end

function ISExpBar:initConfig()
	-- attempt to load config settings from file
	if barHandle:readConfig() == true then
		barHandle:writeConfig(); -- write default config settings to new file if no file exists
	end
end

function ISExpBar:addDropdownPanel()
	local panel;
	--panel = ISExpDropdown:new(200, 200, 80, 32);
	panel = ISExpDropdown:new(
			200, 
			200, 
			80 + (25 * (getCore():getOptionFontSize()-1)), 
			math.floor(getTextManager():getFontHeight(UIFont.Small) * 2)
		);

	panel:initialize();
	panel:instantiate();
	panel:initChildren(self);
	panel:addToUIManager();
	panel:setOpen(false);

	self.dropdownPanel = panel;
end

function ISExpBar:addConfigPanel()
	local panel, label, tickbox, button, pw, ph, tx, ty, tw, th, optionIndex, columnWidth, skillColumns;
	--pw = 180;
	ph = 22;

	columnWidth = math.max(barHandle.longestNameWidth + 80, 180 + (20 * (getCore():getOptionFontSize() - 1)));
	skillColumns = 3;

	pw = columnWidth * skillColumns;

	panel = ISPanel:new(0, 0, pw, ph);
	panel:initialise();
	panel:instantiate();
	panel.backgroundColor = {r=self.backgroundColor.r, g=self.backgroundColor.g, b=self.backgroundColor.b, a=0.8};
	panel.borderColor = self.borderColor_inner;
	panel:setCapture(false);

	-- Title label
	label = ISLabel:new(10, 8, 20, "Tracked Skills:", 1.0, 1.0, 1.0, 1.0, UIFont.Small, true);
	label:initialise();
	label:setVisible(true);

	panel:addChild(label);

	-- Option tickbox
	tx = 10;
	ty = 35;
	--tw = 10;
	--th = 10;
	th = getTextManager():getFontHeight(UIFont.Small);
	tw = th;

	local skillCount, skillCountTotal, skillRows, skillDoTrack, skillType, moddedSkillList, moddedSkillCount, nameWidth, nameWidthLongest, columnWidthDynamic, tickboxHeightMax;

	-- Build a list of modded skills
	moddedSkillList = {};
	for pair in pairs(self.conf_trackSkill) do
		if not self:skillIsBaseGame(pair) then
			--print("ISExpBar(): Modded skill ", pair);
			table.insert(moddedSkillList, pair)
		end
	end
	moddedSkillCount = #moddedSkillList;
	--print("ISExpBar(): moddedSkillCount ", moddedSkillCount);

	skillCount = #self.skill_order;
	skillCountTotal = skillCount + moddedSkillCount;
	skillRows = math.ceil(skillCountTotal / skillColumns);
	tickboxHeightMax = 0;

	-- Add the base skills in order first, then add any modded skills at the end
	for column=1, skillColumns, 1 do
		tickbox = ISTickBox:new(tx, ty, tw, th, "", self, ISExpBar.doTrackTickbox, 1, 2);
		tickbox:initialise();
		tickbox:setVisible(true);
		optionIndex = 1
		nameWidthLongest = 0;

		for skillIndex=1+((column-1)*skillRows), (column*skillRows), 1 do
			nameWidth = 0;
			if skillIndex <= skillCount then
				-- Base game skill
				skillType = self.skill_order[skillIndex];
				skillDoTrack = self.conf_trackSkill[skillType];
				if skillDoTrack ~= nil then
					--print("ISExpBar(): Adding base skill: ", skillType);
					tickbox:addOption(self:getPerkNameFromType(skillType), optionIndex, self:getIcon(skillType));
					tickbox:setSelected(optionIndex, skillDoTrack);
					optionIndex = optionIndex + 1;

					nameWidth = getTextManager():MeasureStringX(UIFont.Small, self:getPerkNameFromType(skillType));
				end
			elseif skillIndex <= skillCount + moddedSkillCount then
				-- Modded skill
				skillType = moddedSkillList[skillIndex-skillCount]
				if skillType ~= nil then
					--print("ISExpBar(): Adding non-base skill: ", skillType);
					tickbox:addOption(self:getPerkNameFromType(skillType), optionIndex, self:getIcon(skillType));
					tickbox:setSelected(optionIndex, self.conf_trackSkill[skillType]);
					optionIndex = optionIndex + 1;

					nameWidth = getTextManager():MeasureStringX(UIFont.Small, self:getPerkNameFromType(skillType));
				else
					print("ISExpBar(): Null skill encountered when trying to add modded skill.");
				end
			end

			if nameWidth > nameWidthLongest then
				nameWidthLongest = nameWidth;
			end
		end

		-- Dynamically reduce the column width if longest name is shorter than base coumns size
		columnWidthDynamic = math.min(columnWidth, nameWidthLongest + 80);
		tx = tx + columnWidthDynamic;
		pw = pw + (columnWidthDynamic-columnWidth);

		-- The tickbox sizes itself as options are added, so ask it how tall it ended up
		if tickbox:getHeight() > tickboxHeightMax then
			tickboxHeightMax = tickbox:getHeight();
		end

		panel:addChild(tickbox);
	end

	ph = ty + tickboxHeightMax + 47;
	panel:setHeight(ph);
	panel:setWidth(pw);

	-- Close button
	button = ISButton:new(math.floor(pw * .5) - 32, ph - 38, 64, 28, "Close", self, ISExpBar.closeConfigPanel);
	button:initialise();
	button.backgroundColor = 	{r=0.22, g=0.19, b=0.14, a=1.0};
	button.borderColor = self.borderColor_inner;
	button:setVisible(true);

	panel:addChild(button);

	panel:setVisible(false);
	panel:addToUIManager();

	self.configPanel = panel;
end

function ISExpBar:skillIsBaseGame(skill_type)
	local skillCount, skillIndex;
	skillCount = #self.skill_order;

	for skillIndex=1, skillCount, 1 do
		if self.skill_order[skillIndex] == skill_type then
			return true;
		end
	end

	return false;
end

function ISExpBar:closeConfigPanel()
	if self.configPanel ~= nil then
		self.configPanel:setVisible(false);
	end
end

function ISExpBar:openConfigPanel()
	if self.configPanel ~= nil then
		self.configPanel:setVisible(true);
		self.configPanel:setX(math.floor( (getCore():getScreenWidth()*0.5) - (self.configPanel:getWidth() * 0.5)));
		self.configPanel:setY(math.floor( (getCore():getScreenHeight()*0.5) - (self.configPanel:getHeight() * 0.5)));
	end
end


function ISExpBar:doTrackTickbox(target, option, arg1, arg2, tickbox)
	if tickbox ~= nil and tickbox.optionsIndex ~= nil then
		local tickboxSkill;
		tickboxSkill = tickbox.optionsIndex[target];
		if tickboxSkill ~= nil then
			self:setTrackSkill(self:getPerkTypeFromName(tickboxSkill), option);
		end
	end
end

function ISExpBar:getPerkTypeFromName(perkName)
	local perkType, perk;
	perkType = perkName;

	for i=1,Perks.getMaxIndex() do
		perk = PerkFactory.getPerk(Perks.fromIndex(i - 1));
		if perk and perk:getParent() ~= Perks.None then
			if perk:getName()==perkName then
				perkType = tostring(perk:getType());
				break;
			end
		end
	end

	--print("ISExpBar(): perkName '".. perkName .. "' resolved as perkType '".. perkType .."'");

	return perkType;
end

function ISExpBar:getPerkNameFromType(perkType)
	local perkName, perk;
	perkName = perkType;

	perk = PerkFactory.getPerk(Perks.FromString(perkType));
	if perk ~= nil then
		perkName = perk:getName();
	end

	--print("ISExpBar(): perkType '".. perkType .. "' resolved as perkName '".. perkName .."'");

	return perkName;
end

function ISExpBar:dropdownPanelIsOpen()
	local panelIsOpen;
	panelIsOpen = false;

	if self.dropdownPanel ~= nil then
		panelIsOpen = self.dropdownPanel:getOpen();
	end

	return panelIsOpen;
end

function ISExpBar:setButtonMode(button_mode, skipMove)
	if self.button_mode ~= button_mode then
		self.button_mode = button_mode;

		if self.button_mode then
			self:setWidth(self.button_w);
			self:setHeight(self.button_h);

			if not skipMove then
				self:setX(self:getX() + self.button_offset_x);
				self:setY(self:getY() + self.button_offset_y);
			end
			self:expDrop_clear();
		else
			if not skipMove then
				self:setX(self:getX() - self.button_offset_x);
				self:setY(self:getY() - self.button_offset_y);
			end
			self:setWidth(self.baseWidth);
			self:setHeight(self.baseHeight);
		end

		if self.dropdownPanel ~= nil then
			self.dropdownPanel.expBar_isOpen = not button_mode;
			self.dropdownPanel:updateHideButton();
		end
	end
end

function ISExpBar:getPerkIndex(skill_type)
	return self.perkIndices[skill_type];
end

function ISExpBar:getPerkFromSkill(skill_type)
	local perkIndex, perk;
	perk = nil;
	perkIndex = self:getPerkIndex(skill_type);

	if perkIndex ~= nil then 
		perk = PerkFactory.getPerk(Perks.fromIndex(perkIndex));
	end

	return perk
end

function ISExpBar:setTrackSkill(skill_type, doTrack)
	self.conf_trackSkill[skill_type] = doTrack;
end

function ISExpBar:getTrackSkill(skill_type)
	if self.conf_trackSkill[skill_type] ~= nil then
		return self.conf_trackSkill[skill_type];
	end

	return true;
end

function ISExpBar:loadSprite(sprite_name)
	print("ISExpBar(): Attempting to load icon for perk:", sprite_name);
	local filename_icon;
	filename_icon = "media/ui/RUNE-EXP_icon_"..tostring(sprite_name):lower():gsub(" ", "_")..".png";

	self.sprites[sprite_name] = getTexture(filename_icon);

	if self.sprites[sprite_name] == nil then
		print("ISExpBar(): Failed to load file:", filename_icon);
	end
end

function ISExpBar:readConfig()
	local fileStream, readLine, splitLine, failed, readConfigVersion;
	failed = true;
	readConfigVersion = false;

	fileStream = getFileReader("RUNE_EXP_conf.ini", true);
	if fileStream ~= nil then
		print("ISExpBar(): Opened config file for reading...")
		readLine = fileStream:readLine();

		if readLine ~= nil then
			failed = false;

			while readLine ~= nil do
				--print("ISExpBar(): Read line as: ", readLine);

				splitLine = string.split(readLine, "=");
				if splitLine~=nil and #splitLine==2 then
					if not readConfigVersion then
						if splitLine[1] == "CONFIG_VERSION" and tonumber(splitLine[2]) == self.CONFIG_VERSION then
							readConfigVersion = true;
							print("ISExpBar(): Read CONFIG_VERSION as current version:", splitLine[2], self.CONFIG_VERSION);
						else
							print("ISExpBar(): Read CONFIG_VERSION as incorrect version:", splitLine[2], self.CONFIG_VERSION);
							failed = true;
							break;
						end
					else

						if splitLine[1] == "pos_x" then
							self:setX(tonumber(splitLine[2]));
						elseif splitLine[1] == "pos_y" then
							self:setY(tonumber(splitLine[2]));
						elseif splitLine[1] == "isHidden" then
							self:setButtonMode((splitLine[2]==tostring(true)), true);
						elseif splitLine[1] == "lastSkill" then
							if self:getPerkIndex(splitLine[2]) ~= nil then
								self:setSkill(splitLine[2]);
							end
						else
							if self:getPerkIndex(splitLine[1]) ~= nil then
								self:setTrackSkill(splitLine[1], (splitLine[2]==tostring(true)));
							end
						end
					end

					--print("ISExpBar(): Read skill " .. splitLine[1] .. " with doTrack " .. splitLine[2] .. " (alt. " .. tostring(splitLine[2]==tostring(true)) ..")")
				else
					print("ISExpBar(): Could not parse line: ", splitLine);
				end
				readLine = fileStream:readLine();
			end
		else
			print("ISExpBar(): Failed to read config file...")
		end

		fileStream:close();
		print("ISExpBar(): Closed config file.")
	else
		print("ISExpBar(): Failed to open config file for reading...")
	end

	return failed;
end

function ISExpBar:writeConfig()
	local fileStream;
	fileStream = getFileWriter("RUNE_EXP_conf.ini", true, false);

	if fileStream ~= nil then
		print("ISExpBar(): Opened config file for writing...")
		
		fileStream:write("CONFIG_VERSION="..tostring(self.CONFIG_VERSION).."\n");
		fileStream:write("pos_x="..tostring(self:getX()).."\n");
		fileStream:write("pos_y="..tostring(self:getY()).."\n");
		fileStream:write("isHidden="..tostring(self.button_mode).."\n");
		fileStream:write("lastSkill="..tostring(self.skill_current).."\n");

		for skill_type, doTrack in pairs(self.conf_trackSkill) do
			fileStream:write(skill_type .. "=" .. tostring(doTrack) .. "\n");
		end

		fileStream:close();
		print("ISExpBar(): Closed config file.")
	else
		print("ISExpBar(): Failed to open config file for writing...")
	end

end

function ISExpBar:skillIsPassive(skill_type)
	return skill_type=="Fitness" or skill_type=="Strength";
end

function ISExpBar:skillIsRounded(skill_type)
	return (self.skill_roundedExp[skill_type] ~= nil);
end

function ISExpBar:skillGetRoundedExp(skill_type, amount)
	local amount_round, perk, xp;
	amount_round = amount;

	perk = self:getPerkFromSkill(skill_type);

	if perk ~= nil then
		xp = self.player:getXp():getXP(perk);
		amount_round = math.floor(xp) - math.floor(xp - amount);
	end

	return amount_round;
end

function ISExpBar:skillGetTable(skill_type)
	return self.skill_expTable[skill_type];
	--if self:skillIsPassive(skill_type) then
	--	return self.expTable_passive;
	--end
	--return self.expTable_normal;
end

function ISExpBar:getExpMax(skill_type, level)
	local expTable;
	expTable = self:skillGetTable(skill_type);
	level = math.max(0, math.min(level+1, 10));

	--return self:cleanExp(expTable, level, expTable[level]);
	return expTable[level];
end

function ISExpBar:getExpCurrent(skill_type, level, exp)
	local expTable;
	expTable = self:skillGetTable(skill_type);
	level = math.max(0, math.min(level, 10));

	return self:cleanExp(expTable, level, exp);
end

function ISExpBar:cleanExp(expTable, level, exp)
	for i=1,level,1 do
		exp = exp - expTable[i];
	end

	return exp;
end

-- Beyond Ten Skills (workshop id 3765241705) raises the level cap to 15. It parks
-- the exp map of a maxed skill at the level 9 total and keeps everything past
-- level 10 in a store of its own, so reading the exp map alone reports a maxed
-- skill as being 10 levels' worth of exp short. Both helpers below fall back to
-- the plain reading when that mod is not loaded.

function ISExpBar:getMasteryExpReader()
	-- Exp that Beyond Ten holds outside the exp map, or nil when it isn't loaded
	if BeyondTen ~= nil and type(BeyondTen.GetStoredXP) == "function" then
		return BeyondTen.GetStoredXP;
	end

	return nil;
end

function ISExpBar:getSkillProgress(skill_type, perk)
	local lvl, xp, xp_max;

	if BeyondTen ~= nil and type(BeyondTen.GetLevelProgress) == "function" then
		local ok;
		ok, lvl, xp, xp_max = pcall(BeyondTen.GetLevelProgress, self.player, perk);
		if ok and lvl ~= nil then
			return lvl, xp, xp_max;
		end
	end

	lvl = self.player:getPerkLevel(perk);
	xp = self.player:getXp():getXP(perk);

	return lvl, self:getExpCurrent(skill_type, lvl, xp), self:getExpMax(skill_type, lvl);
end

function ISExpBar:setSkill(perkType)
	local perk;
	perk = PerkFactory.getPerk(Perks.FromString(perkType));
	if perk ~= nil then
		self.skill_current = perkType;
		self.skill_current_displayName = perk:getName();
		self.sprite = self:getIcon(perkType);

		--print("ISExpBar(): Set skill to:", self.skill_current, self.skill_current_displayName);
	--else
		--print("ISExpBar(): Failed to find perk for skill:", perkType);
	end
end

function ISExpBar:getIcon(skill_type)
	if self.sprites[skill_type] ~= nil then
		return self.sprites[skill_type];
	else
		-- try to load the texture again
		local tmp_spr;
		tmp_spr = getTexture("media/ui/RUNE-EXP_icon_"..skill_type:lower():gsub(" ", "_")..".png");
		if tmp_spr ~= nil then
			return tmp_spr;
		end

		return self.sprites["Unknown"];
	end
end

function ISExpBar:expDrop_clear()
	local count;
	count = #self.expDrops;

	for i=1,count,1 do
		table.remove(self.expDrops);
	end
end

function ISExpBar:expDrop(perk, amount)
	local skill_type;
	skill_type = tostring(perk:getType());

	if not self.button_mode then
		if self:getTrackSkill(skill_type) then
			if self:skillIsRounded(skill_type) then
				amount = self:skillGetRoundedExp(skill_type, amount);
			end

			if amount ~= 0.0 then

				-- Check if we need to queue the exp drop or if we can drop it immediately
				local dropIndex, offset_y, skipDrop;
				dropIndex = #self.expDrops + 1;
				offset_y = 0;
				skipDrop = false;

				if dropIndex > self.expDrop_varCount then
					local alpha_prev;
					alpha_prev = self.expDrops[dropIndex - self.expDrop_varCount + self.expDrop_alpha];
					if alpha_prev <= 0.06 and self.expDrops[dropIndex - self.expDrop_varCount + self.expDrop_skillType] == skill_type then
						self.expDrops[dropIndex - self.expDrop_varCount + self.expDrop_expAmount] = self.expDrops[dropIndex - self.expDrop_varCount + self.expDrop_expAmount] + amount;
						skipDrop = true;
						--print("ISExpBar(): Updated exp amount of previous drop index", dropIndex)
					else
						local dist_prev;
						dist_prev = self:getExpDropDistance(dropIndex - self.expDrop_varCount);
						if dist_prev > self.drop_distance - 12 then
							if dist_prev > self.drop_distance + self.drop_distance_limit then
								--print("ISExpBar(): Queued expDrop due to dist_prev ", dist_prev)
								self:expDropCue(skill_type, amount, perk);
								skipDrop = true;
							else
								offset_y = dist_prev - self.drop_distance + 20;
							end
						end
					end
				end

				if not skipDrop then
					-- Create a new exp drop
					self:setSkill(skill_type)

					self.expDrops[dropIndex + self.expDrop_skillType] = skill_type;
					self.expDrops[dropIndex + self.expDrop_skillDisplayName] = perk:getName();
					self.expDrops[dropIndex + self.expDrop_expAmount] = amount;
					self.expDrops[dropIndex + self.expDrop_alpha] = 0;
					self.expDrops[dropIndex + self.expDrop_offset] = offset_y;
				end
			end
		end
	end
end

function ISExpBar:expDropCue(skill_type, amount, perk)
	local varCount, queueIndex, queueIndex_new, addToQueue;
	varCount = self.queue_varCount;
	queueIndex_new = #self.dropQueue + 1;
	queueIndex = queueIndex_new - varCount;
	addToQueue = true;

	while queueIndex >= 1 do
		if self.dropQueue[queueIndex + self.queue_skillType] == skill_type then
			addToQueue = false
			self.dropQueue[queueIndex + self.queue_expAmount] = self.dropQueue[queueIndex + self.queue_expAmount] + amount;
			--print("ISExpBar(): Appended existing queue entry ", skill_type, amount)
			break
		end
		queueIndex = queueIndex - varCount;
	end

	if addToQueue then
		--print("ISExpBar(): Added new queue entry ", skill_type, amount)
		self.dropQueue[queueIndex_new + self.queue_skillType] = skill_type;
		self.dropQueue[queueIndex_new + self.queue_expAmount] = amount;
		self.dropQueue[queueIndex_new + self.queue_perk] = perk;
	end
end

function ISExpBar:updateQueue()
	local queueIndex, varCount, dropIndex, popQueue;
	varCount = self.queue_varCount;
	queueIndex = (#self.dropQueue + 1) - varCount;
	popQueue = false;

	if queueIndex >= 1 then
		dropIndex = #self.expDrops + 1 - self.expDrop_varCount;
		if dropIndex >= 1 then
			popQueue = (self:getExpDropDistance(dropIndex) < self.drop_distance - self.drop_sep_min);
		else
			popQueue = true;
		end
	end

	if popQueue then
		--print("ISExpBar(): Popping queue index ", queueIndex)
		self:expDrop(self.dropQueue[queueIndex + self.queue_perk], self.dropQueue[queueIndex + self.queue_expAmount]);

		for i=1,varCount,1 do
			table.remove(self.dropQueue, queueIndex);
		end
	end
end

function ISExpBar:getExpDropDistance(dropIndex)
	-- Get the current y postion for the specified exp drop
	local dist;
	dist = 0;

	if dropIndex + self.expDrop_varCount <= #self.expDrops + 1 then
		local alpha;
		alpha = self:tween_powerInOut(1 - self.expDrops[dropIndex + self.expDrop_alpha], 2.0);
		dist = self.expDrops[dropIndex + self.expDrop_offset] + (self.drop_distance * alpha);
	end

	return dist;
end

function ISExpBar:updateExpDrops()
	-- Update the alpha value for all active exp drops
	local varCount, dropIndex, alpha;
	varCount = self.expDrop_varCount;
	dropIndex = (#self.expDrops + 1) - varCount;

	while dropIndex >= 1 do
		alpha = self.expDrops[dropIndex + self.expDrop_alpha];
		alpha = alpha + 0.015;

		if alpha >= 1 then
			-- Remove this drop entry
			for i=1,varCount,1 do
				table.remove(self.expDrops, dropIndex);
			end
		else
			-- Store updated alpha value for this drop entry
			self.expDrops[dropIndex + self.expDrop_alpha] = alpha;
		end
		dropIndex = dropIndex - varCount;
	end

	self:updateQueue();
end

function ISExpBar:renderExpDrops()
	local varCount, dropIndex, alpha, spr, amount, a, dx, dy;
	varCount = self.expDrop_varCount;
	dropIndex = (#self.expDrops + 1) - varCount;

	while dropIndex >= 1 do
		spr = self:getIcon(self.expDrops[dropIndex + self.expDrop_skillType]);
		amount = string.format(" %.2f", tostring(self.expDrops[dropIndex + self.expDrop_expAmount]));
		alpha = 1 - self.expDrops[dropIndex + self.expDrop_alpha];

		a = self:tween_powerOut(alpha, 0.5);

		dx = self.drop_x;
		dy = self.icon_y + self.height + self:getExpDropDistance(dropIndex);

		if spr ~= nil then
			self:drawTextureScaled(spr, dx, dy + self.icon_drop_y_offset, self.icon_wh, self.icon_wh, a, 1, 1, 1);
		end

		dx = self.width - 4;
		dy = dy + self.bar_translationOffset_y + 2;

		self:drawTextRight(amount, dx + 2, dy + 2, 0, 0, 0, a, UIFont.Medium);
		self:drawTextRight(amount, dx, dy, 1, 1, 1, a, UIFont.Medium);

		dropIndex = dropIndex - varCount;
	end
end

function ISExpBar:renderTooltip(skill_displayName, lvl, xp, xp_max)
	local tx, maxX, minX;
	minX = -self:getX();
	maxX = (getCore():getScreenWidth() - self:getX());

	tx = math.max(minX, self.tooltip_x);

	if tx + self.tooltip_w > maxX then
		tx = -(self.tooltip_w - maxX);
	end

	self:drawRectStatic(tx, self.tooltip_y, self.tooltip_w, self.tooltip_h, 1.0, self.tooltip_colour.r, self.tooltip_colour.g, self.tooltip_colour.b);
	self:drawRectBorderStatic(tx, self.tooltip_y, self.tooltip_w, self.tooltip_h, 1.0, 0.0, 0.0, 0.0);

	local str_left, str_right, exp_prog;
	str_left = skill_displayName .. "  (Lvl " .. tostring(lvl) .. ")" .. "\n\nCurrent:\nNext Level:\n\nRemaining:";
	--str_right = "Lvl " .. tostring(lvl) .. "\n\n" .. string.format("%.2f", tostring(xp)) .. "\n" .. string.format("%.2f", tostring(xp_max)) .. "\n\n" .. string.format("%.2f", tostring(xp_max-xp));

	self:drawText(str_left, tx + self.tooltip_text_offset_x, self.tooltip_y + self.tooltip_text_offset_y, 0, 0, 0, 1.0, UIFont.Small);
	--self:drawTextRight(str_right, tx + self.tooltip_w - 5, self.tooltip_y + 5, 0, 0, 0, 1.0, UIFont.Small);

	exp_prog = math.floor(xp);
	if exp_prog ~= 0 and xp_max ~= 0 then
		exp_prog = math.floor((xp / xp_max) * 100);
	else
		exp_prog = 0;
	end

	-- have to do multiple calls to properly align the text to the right
	--str_right = "Lvl " .. tostring(lvl);
	str_right = tostring(exp_prog) .. "%";
	self:drawTextRight(str_right, tx + self.tooltip_w - self.tooltip_text_offset_x, self.tooltip_y + self.tooltip_text_offset_y, 0, 0, 0, 1.0, UIFont.Small);

	str_right = "\n\n" .. string.format("%.2f", tostring(xp));
	self:drawTextRight(str_right, tx + self.tooltip_w - self.tooltip_text_offset_x, self.tooltip_y + self.tooltip_text_offset_y, 0, 0, 0, 1.0, UIFont.Small);

	str_right = "\n\n\n" .. string.format("%.2f", tostring(xp_max));
	self:drawTextRight(str_right, tx + self.tooltip_w - self.tooltip_text_offset_x, self.tooltip_y + self.tooltip_text_offset_y, 0, 0, 0, 1.0, UIFont.Small);

	str_right = "\n\n\n\n\n" .. string.format("%.2f", tostring(xp_max-xp));
	self:drawTextRight(str_right, tx + self.tooltip_w - self.tooltip_text_offset_x, self.tooltip_y + self.tooltip_text_offset_y, 0, 0, 0, 1.0, UIFont.Small);
end

function ISExpBar:prerender()
	if self.xpPoll then
		self:pollXpChanges();
	end

	if self.button_mode then
		-- hidden XP button

		if self.button_sprite == nil then
			-- attempt to reload the texture
			self.button_sprite = getTexture("media/ui/RUNE-EXP_XpButton.png");
		end

		if self.button_sprite ~= nil then
			self:drawTextureScaled(self.button_sprite, 0, 0, self.button_w, self.button_h, 1, 1, 1, 1);
		else
			self:drawRectStatic(0, 0, self.button_w, self.button_h, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b);
			self:drawRectBorderStatic(0, 0, self.button_w, self.button_h, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b);
			self:drawRectBorderStatic(1, 1, self.button_w - 2, self.button_h - 2, self.borderColor_inner.a, self.borderColor_inner.r, self.borderColor_inner.g, self.borderColor_inner.b);
		end

	else
		self:updateExpDrops();

		if self.background then
			-- exp drops
			self:renderExpDrops();

			-- frame
			self:drawRectStatic(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b);
			self:drawRectBorderStatic(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b);
			self:drawRectBorderStatic(1, 1, self.width - 2, self.height - 2, self.borderColor_inner.a, self.borderColor_inner.r, self.borderColor_inner.g, self.borderColor_inner.b);

			
			-- exp bar
			self:drawRectStatic(self.bar_x + 1, self.bar_y + 1, self.bar_w - 2, self.bar_h - 2, self.colour_black.a, self.colour_black.r, self.colour_black.g, self.colour_black.b);

			local perk, xp, xp_max, lvl;
			perk = self:getPerkFromSkill(self.skill_current);
			xp = 0;
			xp_max = 0;
			lvl = 0;

			if perk ~= nil then
				local barAlpha;
				lvl, xp, xp_max = self:getSkillProgress(self.skill_current, perk);
				xp_max = math.max(1, xp_max);

				barAlpha = xp;
				if barAlpha > 0 then
					barAlpha = math.min(1, barAlpha / xp_max);
				else
					barAlpha = 0;
				end

				if barAlpha ~= 0 then
					self:drawRectStatic(self.bar_x + 2, self.bar_y + 2, (self.bar_w - 4) * barAlpha, self.bar_h - 4, 1, .59 * (1-barAlpha), .59 * barAlpha, 0);
				end

				local exp_string;
				exp_string = string.format("%.2f", tostring(xp));

				self:drawTextRight(exp_string, self.width - 3, self.icon_text_y + self.bar_translationOffset_y + 4, 0, 0, 0, 1, UIFont.Medium);
				self:drawTextRight(exp_string, self.width - 5, self.icon_text_y + self.bar_translationOffset_y + 2, 1, 1, 1, 1, UIFont.Medium);
			end
			
			self:drawRectBorderStatic(self.bar_x, self.bar_y, self.bar_w, self.bar_h, self.borderColor_inner.a, self.borderColor_inner.r, self.borderColor_inner.g, self.borderColor_inner.b);

			-- skill icon
			if self.sprite ~= nil then
				self:drawTextureScaled(self.sprite, self.icon_x, self.icon_y, self.icon_wh, self.icon_wh, 1, 1, 1, 1);
			end

			-- tooltip
			if self.tooltip_visible then
				self:renderTooltip(self.skill_current_displayName, lvl, xp, xp_max);
			end
		end
	end
end

function ISExpBar:tween_powerOut(a, p)
	-- heavily eases out, decreased power gives increased easing
	-- .5 is a good default p value
	if a<=0 then 
		return 0;
	elseif a>=1 then
		return 1;
	end

	-- Desmos pasta: y\ =\ \left(-(x)*\left(x-2\right)\right)^p
	return (-(a * (a-2)))^p;
end

function ISExpBar:tween_powerInOut(a, p)
	-- eases in and out using power, increased power gives increased easing
	-- use '2' as a good default power

	if a<=0 then 
		return 0;
	elseif a>=1 then
		return 1;
	end

	if a<=0.5 then
	    -- Desmos pasta: y\ =\ \frac{\left(2x\right)^p}{2}
	    return ( ((2*a)^p) / 2);
	else
	    -- Desmos pasta: y\ =\ 1\ -\frac{\left(\left(2\cdot\left(1-x\right)\right)^p\right)}{2}
	    return (1 - ( ((2*(1-a))^p) / 2));
	end
end