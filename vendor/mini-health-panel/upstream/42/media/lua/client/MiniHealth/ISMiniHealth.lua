require "ISUI/ISUIElement"

ISMiniHealth = ISPanel:derive("ISMiniHealth")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)

local COLORS = {
	none = Color.new(0,0,0,0),
	untreated = Color.new(1,0,0,1),
	bandaged = Color.new(0.78,0.69,0.6,1),
	healed = Color.new(0.8,1,0.6),
	dirty = Color.new(1,0.57,0.11,1),

	strain = {r=1, g=0.57, b=0.11}
}

function ISMiniHealth:new(playerIndex,player,enabled)
	local bw = 120
	local bh = 271

	local mhpHandle = {}
	mhpHandle = ISPanel:new(25, getCore():getScreenHeight() - bh - 25, bw, bh)
	setmetatable(mhpHandle, self)
	self.__index = self

	mhpHandle.playerIndex = playerIndex
	mhpHandle.player = player
	mhpHandle.player_isDead = false
	mhpHandle.isFemale = player:isFemale();

	mhpHandle.colour = {r=0,g=1,b=0}
	mhpHandle.alpha = 1.0
	mhpHandle.bgAlpha = 0
	mhpHandle.blinkTime = 0
	mhpHandle.blinkAlpha = 0
	mhpHandle.isHover = false
	mhpHandle.baseWidth = bw
	mhpHandle.baseHeight = bh

	mhpHandle.canHide = false
	mhpHandle.hideTimer = 100

	mhpHandle.health = 0
	mhpHandle.previousHealth = 0
	mhpHandle.healthColor = {r=1,g=1,b=1,a=1}
	mhpHandle.infopanel = getPlayerInfoPanel(player:getPlayerNum())

	mhpHandle.moveWithMouse = true
	-- mhpHandle:setCapture(false)

	mhpHandle.rightMouseDown = false
	mhpHandle.dragging = false

	mhpHandle.backgroundColor = 	{r=0.0, g=0.0, b=0.0, a=0.5}
	mhpHandle.borderColor = 		{r=0.4, g=0.4, b=0.4, a=1}
	mhpHandle.colour_black = 		{r=0.0, g=0.0, b=0.0, a=1.0}

	mhpHandle.outlineTex = {
		[false] = getTexture("media/ui/male/mhp-Outline.png"),
		[true] = getTexture("media/ui/female/mhp-Outline.png")
	}
	mhpHandle.backgroundTex = {
		[false] = getTexture("media/ui/male/mhp-background.png"),
		[true] = getTexture("media/ui/female/mhp-background.png")
	}

	mhpHandle.bottomHeight = getTextManager():getFontHeight(UIFont.Small)

	mhpHandle.CONFIG_VERSION = 1
	mhpHandle.alwaysShow = false
	mhpHandle.showHpBar = false
	mhpHandle.showStrains = true
    mhpHandle.settingsPanel = nil
	mhpHandle.latestNews = 0

	mhpHandle.enabled = enabled
	mhpHandle:setVisible(enabled)

	return mhpHandle
end

function ISMiniHealth:initialize()
	ISUIElement.initialise(self)

    self.cacheColor = Color.new(  1.0,  1.0, 1.0, 1.0 )

	-- ==== Body injuries init ====

	self.mhpBodyParts = {}

	for i = 0,16 do
		local type = BodyPartType.FromIndex(i);

		local limb = {
			texture = {
				[false] = getTexture("media/ui/male/mhp-limb_"..i..".png"),
				[true] = getTexture("media/ui/female/mhp-limb_"..i..".png")
			},
			color = Color.new(0,1,0,1),
			alpha = 1.0,
			doBlink = false,
			blinkTime = 0,
			state = nil,
		}
		table.insert(self.mhpBodyParts, limb);
	end

	-- ==== Body strains init ====

	self.mhpBodyStrains = {}

	for i = 0,16 do
		local type = BodyPartType.FromIndex(i);

		local limb = {
			texture = {
				[false] = getTexture("media/ui/male/mhp-stiff_"..i..".png"),
				[true] = getTexture("media/ui/female/mhp-stiff_"..i..".png")
			},
			color = Color.new(0,1,0,1),
			strainAlpha = 1.0,
			renderAlpha = 1.0,
			colorMultiplier = 1,
			r = 1,
			g = 0.57,
			b = 0.11,
			blinkTime = 79,
			nextStage = 5,
			prevStage = -1,
			state = nil,
		}
		table.insert(self.mhpBodyStrains, limb);
	end
end

function ISMiniHealth:createChildren()
	local btnWid = 25
	local btnHgt = getTextManager():getFontHeight(UIFont.Small) - 1

    self.topPanel = ISPanel:new(0, 0, self.baseWidth, btnHgt)
    self.topPanel.backgroundColor =  {r=0.0, g=0.0, b=0.0, a=0.0}
    self.topPanel.borderColor = 		{r=0.0, g=0.0, b=0.0, a=0.0}
    self:addChild(self.topPanel)
    self.topPanel:setVisible(false)

    self.gearButton = ISButton:new(0, 0, btnWid, btnHgt, "", self, ISMiniHealth.onGearButton)
    self.gearButton:initialise()
	self.gearButton.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
    self.gearButton:setImage(getTexture("media/ui/inventoryPanes/Button_Gear.png"))
	self.topPanel:addChild(self.gearButton)
end

function ISMiniHealth:addSettingsPanel()
    local panel

    panel = ISMhpSettings:new(self:getX(),self:getY()+self:getHeight()+2,self:getWidth())
    panel:initialise();
	panel:instantiate();
	panel:createChildren();
    panel:populateOptions();
	panel:addToUIManager();
	panel:setOpen(false);

    self.settingsPanel = panel
end

function ISMiniHealth:settingsPanelPos()
	local x = self:getX()
	local y = self:getY()-self.settingsPanel:getHeight()-2
	local width = self:getWidth()

	if y < 1 then
		y = self:getY() + self:getHeight() + 2
	end

	return x,y,width
end

function ISMiniHealth:onGearButton()
    if not self.player_isDead then
		local x,y,width = self:settingsPanelPos()

        if self.settingsPanel:getOpen() == false then
            self.settingsPanel:setOpen(true, x ,y , width)
        else
            self.settingsPanel:setOpen(false, 0, 0 , 0)
        end
    end
end

function ISMiniHealth:toggleAlwaysShow(selected)
    self.alwaysShow = selected
end

function ISMiniHealth:toggleHpBar(selected)
    self.showHpBar = selected
    if selected then
        self:setWidth(140)
    else
        self:setWidth(120)
    end
end

function ISMiniHealth:toggleStrains(selected)
	self.showStrains = selected
end

function ISMiniHealth:toggleLock(selected)
	self.moveWithMouse = selected
end

function ISMiniHealth:prerender()
	-- frame
	self:drawRectStatic(0, 0, self.width, self.height, self.backgroundColor.a * self.bgAlpha, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b);
	self:drawRectBorderStatic(0, 0, self.width, self.height, self.borderColor.a * self.bgAlpha, self.borderColor.r, self.borderColor.g, self.borderColor.b);
	-- self:drawRectBorderStatic(1, 1, self.width - 2, self.height - 2, self.borderColor_inner.a, self.borderColor_inner.r, self.borderColor_inner.g, self.borderColor_inner.b);

	self:drawTexture(self.backgroundTex[self.isFemale],0,0, 0.5 * self.alpha, 0, 0, 0)
	local outlineColor = (self.health/80)-0.2
	self:drawTexture(self.outlineTex[self.isFemale],0,0, 1 * self.alpha, 1, outlineColor, outlineColor)


	local hasNewsBox = false

	if not self.newsBox then
		hasNewsBox = false
	elseif self.newsBox:isReallyVisible() then
		hasNewsBox = true
	end

	if self:isMouseOver() or hasNewsBox or self.settingsPanel:getOpen() then
		self.isHover = true
		self.bgAlpha = 1
		self.hideTimer = 30
		self.alpha = 1
        self.topPanel:setVisible(true)
	else
		self.isHover = false
		self.bgAlpha = 0
        self.topPanel:setVisible(false)
	end
end

function ISMiniHealth:render()
	local bp
	local blinking = 0

	for i=1, #self.mhpBodyParts do

		-- ==== Body injuries render ====
		bp = self.mhpBodyParts[i]

		if bp.doBlink then
			bp.alpha = self.blinkAlpha
			blinking = blinking + 1
		end

		if bp.alpha > 0 and self.alpha > 0 then
			self:drawTexture(bp.texture[self.isFemale], 0, 0, bp.alpha * self.alpha, bp.color:getRedFloat(), bp.color:getGreenFloat(), bp.color:getBlueFloat())
		end

		-- ==== Body strains render ====
		if not self.player_isDead and self.showStrains then
			st = self.mhpBodyStrains[i]

			if st.blinkTime <= 78 then
				st.blinkTime = st.blinkTime + 1
				st.blinkAlpha = math.abs(math.sin(st.blinkTime/10))
			end

			if st.blinkTime < 78 then
				st.renderAlpha = st.strainAlpha * st.blinkAlpha
			elseif bp.doBlink then
				st.renderAlpha = st.strainAlpha * (1 - self.blinkAlpha)
			else
				st.renderAlpha = st.strainAlpha
			end

			if st.strainAlpha > 0 and self.alpha > 0 then
				self:drawTexture(st.texture[self.isFemale], 0, 0, st.renderAlpha * self.alpha, st.r, st.g, st.b)
			end
		end
	end

	if blinking > 0 then
		self.blinkTime = self.blinkTime + 1
		self.blinkAlpha = math.abs(math.sin(self.blinkTime/10))
	else
		self.blinkTime = 0
		self.blinkAlpha = 0
	end

	if self.showHpBar then
		local hpHeight = (self.health / 100) * 260
		self:drawRectStatic( 123,267,14,-264,0.5 * self.alpha,0,0,0)
		self:drawRectStatic( 125,265,10,-hpHeight,1 * self.alpha,self.healthColor.r,self.healthColor.g,self.healthColor.b)
	end

	if not self.isHover then
		if self.hideTimer <= 0 then
			self.alpha = math.max(self.alpha - 0.05,0)
		else
			self.alpha = math.min(self.alpha + 0.05,1)
		end
	end
end


function ISMiniHealth:update()
	local bodyDamage = self.player:getBodyDamage()
	local bodyParts = bodyDamage:getBodyParts()

	local injuries = 0
	local treated = 0

	for i=1, #self.mhpBodyParts do

		-- ==== Body injuries ====
		local bodyPart = bodyParts:get(i-1)
		local limb = self.mhpBodyParts[i]
		
		if bodyPart:HasInjury() or bodyPart:stitched() or bodyPart:bandaged() then
			limb.color = COLORS.untreated
			injuries = injuries + 1

			if bodyPart:bandaged() or bodyPart:getSplintFactor() > 0 then
				limb.color = COLORS.bandaged
				treated = treated + 1

				if bodyPart:getBandageLife() <= 0 then
					limb.color = COLORS.dirty
					treated = treated - 1
				end
			end

		else
			limb.alpha = 0
			limb.doBlink = false
			limb.color = COLORS.none
		end
		
		-- Blink if has wound not bandaged
		if (
				(
					bodyPart:scratched() 
					or bodyPart:deepWounded() 
					or bodyPart:getDeepWoundTime() > 0 
					or bodyPart:bitten() 
					or bodyPart:getFractureTime() > 0
					or bodyPart:stitched() 
					or bodyPart:bleeding() 
					or bodyPart:isBurnt() 
					or bodyPart:isCut() 
					or bodyPart:haveGlass() 
					or bodyPart:haveBullet() 
					or bodyPart:isInfectedWound()
				) and not bodyPart:bandaged()
		)
		-- Blink if bandaged but have severe wound untreated
		or (
			(
				bodyPart:getDeepWoundTime() > 0
				or bodyPart:haveBullet() 
				or bodyPart:haveGlass() 
			) and bodyPart:bandaged()
		)
		or ( bodyPart:getFractureTime() > 0 and bodyPart:getSplintFactor() <= 0)
		then
			limb.doBlink = true
			if bodyPart:getBandageLife() > 0 then
				treated = treated - 1
			end
		elseif (bodyPart:bandaged() and (not bodyPart:haveGlass() or not bodyPart:haveBullet() or bodyPart:getDeepWoundTime() <= 0))
		or (bodyPart:getFractureTime() > 0 and bodyPart:getSplintFactor() > 0) then
			limb.doBlink = false
			limb.alpha = 1.0
		end

		-- ==== Body strains ====
		if self.showStrains then
			
			local strain = self.mhpBodyStrains[i]
			local stiffness = bodyPart:getStiffness()

			if stiffness > 0 then
				strain.strainAlpha = math.min( (stiffness/5), 1) 
			else
				strain.strainAlpha = 0
			end

			if stiffness >= 5 then
				strain.colorMultiplier = math.min( (20-stiffness)/15, 1)
				strain.g = COLORS.strain.g * strain.colorMultiplier
				strain.b = COLORS.strain.b * strain.colorMultiplier
			else
				strain.g = 0.87
				strain.b = 0
			end

			-- ==== Blink on stiffness threshold
			if stiffness >= strain.nextStage or stiffness < strain.prevStage then

				self.hideTimer = 40
				strain.blinkTime = 16

				if stiffness < 5 then
					strain.prevStage = -1
					strain.nextStage = 5
				elseif stiffness >= 5 and stiffness < 20 then
					strain.prevStage = 5
					strain.nextStage = 20
				elseif stiffness >= 20 then
					strain.prevStage = 20
					strain.nextStage = 101
				end

			end
			
		end
	end

	local health = bodyDamage:getHealth()

	self.health = health

	if health >= 100 then
		self.healthColor = {r=1,g=1,b=1,a=1}
	else
		self.healthColor.b = 0
		self.healthColor.g = health/100
	end

	if health < self.previousHealth then
		local moodles = self.player:getMoodles()
		if (
			moodles:getMoodleLevel(MoodleType.HEAVY_LOAD) < 3
			or (
				moodles:getMoodleLevel(MoodleType.SICK) >= 2
				or moodles:getMoodleLevel(MoodleType.HYPOTHERMIA) >= 4
				or moodles:getMoodleLevel(MoodleType.THIRST) >= 4
				or moodles:getMoodleLevel(MoodleType.HUNGRY) >= 4
			)
		) 
		then
			self.hideTimer = 30
		end
	end

	self.previousHealth = health

	if (treated >= injuries) then
		self.canHide = true
	else
		self.canHide = false
	end

	if self.canHide == true and self.alwaysShow == false then
		self.hideTimer = math.max(self.hideTimer - 1,0)
	else
		self.hideTimer = 30
	end

end

-- ===== Handle player death =====

function ISMiniHealth:getPlayer()
	return self.player
end

function ISMiniHealth:setPlayerIsDead(isDead)
	self.player_isDead = isDead

    if self.settingsPanel:getOpen() then
        self.settingsPanel:setOpen(false, 0, 0, 0)
    end
end

function ISMiniHealth:getPlayerIsDead()
	return self.player_isDead
end

function ISMiniHealth:setPlayer(playerIndex,player)
	self.playerIndex = playerIndex
	self.player = player
	self.isFemale = player:isFemale();
	self:setPlayerIsDead(false)
	self.infopanel = getPlayerInfoPanel(player:getPlayerNum())
end

-- ===== Handle screen resolution change =====
function ISMiniHealth:checkNewResolution()
	local screenH = getCore():getScreenHeight()
	local screenW = getCore():getScreenWidth()

	local posX = self.x
	local posY = self.y
	local width = self.width
	local height = self.height

	if (posX + width) > screenW then
		self:setX(screenW - width)
	end

	if (posY + height) > screenH then
		self:setY(screenH - height)
	end
end

-- ===== Open health panel (and prevent it if moving the mini panel) =====

function ISMiniHealth:onMouseDown(x,y)
	self.rightMouseDown = true

	ISPanel.onMouseDown(self, x, y)
end

function ISMiniHealth:onMouseMove(dx, dy)
	if self.rightMouseDown == true then
		self.dragging = true
	end

	if self.dragging then
		if self.settingsPanel:getOpen() then
			local x,y = self:settingsPanelPos()
			self.settingsPanel:setX(x)
			self.settingsPanel:setY(y)
		end
		if self.newsBox then
			local x,y = self:newsBoxPos()
			self.newsBox:setX(x)
			self.newsBox:setY(y)
		end
	end

	ISPanel.onMouseMove(self, dx, dy)
end

function ISMiniHealth:onMouseUp(x,y)

	if not self.dragging and not self.player_isDead then
		getSoundManager():playUISound("UISelectListItem")
		self.infopanel:toggleView(getText("IGUI_XP_Health"))
	end

	self.dragging = false
	self.rightMouseDown = false

	ISPanel.onMouseUp(self, x, y)
end


ISMiniHealth.haveDamagePart = function (player)
	local result = {}
	local bodyParts = getSpecificPlayer(player):getBodyDamage():getBodyParts();

	for i=0,BodyPartType.ToIndex(BodyPartType.MAX) - 1 do
		local bodyPart = bodyParts:get(i);
		-- if it's damaged
		if bodyPart:scratched() 
		or bodyPart:deepWounded()
		or bodyPart:getDeepWoundTime() > 0 
		or bodyPart:bitten() 
		or bodyPart:getFractureTime() > 0
		or bodyPart:stitched() 
		or bodyPart:bleeding() 
		or bodyPart:isBurnt() 
		or bodyPart:isCut()
		or bodyPart:haveGlass() 
		or bodyPart:haveBullet() 
		or bodyPart:isInfectedWound()
		or bodyPart:bandaged() then
			table.insert(result, bodyPart);
		end
	end

	return result;
end

ISMiniHealth.getInjuryType = function(bodyPart)

	local text = ""
	local redText = true

	if bodyPart:bleeding() then
		text = getText("IGUI_health_Bleeding")
	end
	if bodyPart:scratched() then 
		text = getText("IGUI_health_Scratched")
	end
	if bodyPart:isCut() then
		text = getText("IGUI_health_Cut")
	end
	if bodyPart:bitten() then
		text = getText("IGUI_health_Bitten")
	end
	if bodyPart:getFractureTime() > 0 and bodyPart:getSplintFactor() == 0 then
		text = getText("IGUI_health_Fracture")
	end
	if bodyPart:getSplintFactor() > 0 then
		text = getText("IGUI_health_Splinted")
		redText = false
	end
	if bodyPart:bandaged() and bodyPart:getBandageLife() > 0 then
		text = getText("IGUI_health_Bandaged")
		redText = false
	end
	if bodyPart:bandaged() and bodyPart:getBandageLife() <= 0 then
		text = getText("IGUI_health_DirtyBandage")
	end

	if bodyPart:getBurnTime() > 0 and not bodyPart:bandaged() then
		text = getText("IGUI_health_Burned")
	end
	if bodyPart:stitched() then
		text = getText("IGUI_health_Stitched")
	end
	if bodyPart:isInfectedWound() and not bodyPart:bandaged() then
		text = text.." - "..getText("IGUI_health_Infected")
	end

	if bodyPart:getDeepWoundTime() > 0 then
		if bodyPart:bandaged() or bodyPart:stitched() then
			text = text.." - "..getText("IGUI_health_DeepWound")
			redText = true
		else
			text = getText("IGUI_health_DeepWound")
		end
	end
	if bodyPart:haveGlass() then
		if bodyPart:bandaged() or bodyPart:stitched() then
			text = text.." - "..getText("IGUI_health_LodgedGlassShards")
		else bodyPart:bandaged()
			text = getText("IGUI_health_LodgedGlassShards")
		end
	end
	if bodyPart:haveBullet() then
		if bodyPart:bandaged() or bodyPart:stitched() then
			text = text.." - "..getText("IGUI_health_LodgedBullet")
		else bodyPart:bandaged()
			text = getText("IGUI_health_LodgedBullet")
		end
	end

	return text,redText
end

-- ===== Context menu ====
local contextMenu = nil

function ISMiniHealth:onRightMouseUp(x,y, ...)
	if not self.player_isDead then
		mhpHandle:showContextMenu(self, x, y)
	end
end

function ISMiniHealth:showContextMenu(miniHealth, x, y)
	local contextMenu = ISContextMenu.get(
        miniHealth.playerIndex, 
        (miniHealth:getX()+x), (miniHealth:getY()+y), 
        1, 1
    )

	local bodyPartDamaged = ISMiniHealth.haveDamagePart(self.playerIndex)

	if #bodyPartDamaged > 0 then
        for i,v in ipairs(bodyPartDamaged) do
			local injuryType,redText = ISMiniHealth.getInjuryType(v)
            local bodyPartOption = contextMenu:addOption(BodyPartType.getDisplayName(v:getType()).." ("..injuryType..")", miniHealth, nil);
			bodyPartOption.notAvailable = redText
			local bodyPartSubMenu = ISContextMenu:getNew(contextMenu)
			contextMenu:addSubMenu(bodyPartOption, bodyPartSubMenu)

			MiniHealthTreatment:doBodyPartContextMenu(v, bodyPartSubMenu)
        end
    else
		contextMenu:addOption(getText("IGUI_Beard_None").." "..getText("IGUI_ItemCat_Wound"), nil, nil)
	end

	local boolText = {
		[true] = "ON",
		[false] = "OFF"
	}

end


-- ===== Config =====

function ISMiniHealth:onModOptionsApply(enabled)
	self:setVisible(enabled)

	if enabled and not self.enabled then

		self:addToUIManager()

		if self.newsBox then
			self.newsBox:addToUIManager()
			self.newsBox:setVisible(true)
		end

	elseif not enabled and self.enabled then

		if self.newsBox then
			if self.newsBox:isReallyVisible() then
				self.newsBox:setVisible(false)
				self.newsBox:removeFromUIManager()
			end
		end

		if self.settingsPanel:getOpen() then
			self.settingsPanel:setOpen(false, 0, 0 , 0)
		end

		self:removeFromUIManager()

	end

	self.enabled = enabled
end

function ISMiniHealth:newsBoxPos()
	local x = self:getX() + self:getWidth() + 2
	local y = self:getY()
	local screenWidth = getCore():getScreenWidth()
	local newsBoxWidth = self.newsBox:getWidth()

	if (x + newsBoxWidth) > screenWidth then
		x = self:getX() - newsBoxWidth - 2
	end

	return x,y
end

function ISMiniHealth:initConfig()
	if mhpHandle:readConfig() == true then
		mhpHandle:writeConfig()
	end

	local newsVersion = "1.6.1 b42"

	if self.latestNews ~= newsVersion and not self.newsBox then
		self.newsBox = ISModalRichText:new(0,0,530,200,getText("IGUI_MiniHealth_UpdateNotes"), false, nil, function() ISMiniHealth:dismissedUpdate(newsVersion) end);
		self.newsBox:initialise()
		self.newsBox:addToUIManager()
		self.newsBox.chatText:paginate()
		self.newsBox.backgroundColor = {r=0, g=0, b=0, a=0.5}

		self.newsBox:setHeight(self.newsBox.chatText:getHeight() + 20)
		local x,y = self:newsBoxPos()
		self.newsBox:setX(x)
		self.newsBox:setY(y)

		self.newsBox:setVisible(true)
		self.newsBox:setAlwaysOnTop(true)
	end

	if not self.enabled then
		self.newsBox:setVisible(false)
		self.newsBox:removeFromUIManager()
	end
end

function ISMiniHealth:dismissedUpdate(version)
	print("ISMiniHealth(): News dismissed and settings updated: "..version)
	mhpHandle.latestNews = version
end

function ISMiniHealth:readConfig()
	local fileStream, readLine, splitLine, failed, readConfigVersion;
	failed = true;
	readConfigVersion = false;

	fileStream = getFileReader("Mini_health_conf.ini", true);
	if fileStream ~= nil then
		print("ISMiniHealth(): config file for reading...")
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
							print("ISMiniHealth(): Read CONFIG_VERSION as current version:", splitLine[2], self.CONFIG_VERSION);
						else
							print("ISMiniHealth(): Read CONFIG_VERSION as incorrect version:", splitLine[2], self.CONFIG_VERSION);
							failed = true;
							break;
						end
					else

						if splitLine[1] == "pos_x" then
							local posX = tonumber(splitLine[2])
							self:setX(posX)

						elseif splitLine[1] == "pos_y" then
							local posY = tonumber(splitLine[2])
							self:setY(posY)

						elseif splitLine[1] == "alwaysShow" and splitLine[2] == "true" then

							self.alwaysShow = true

						elseif splitLine[1] == "showHpBar" and splitLine[2] == "true" then
							
							self.showHpBar = true
							self:setWidth(140)

						elseif splitLine[1] == "showStrains" and splitLine[2] == "false" then
							
							self.showStrains = false

						elseif splitLine[1] == "moveWithMouse" and splitLine[2] == "false" then
							self.moveWithMouse = false
						elseif splitLine[1] == "latestNews" then
							self.latestNews = tostring(splitLine[2])
						end
					end

				else
					print("ISMiniHealth(): Could not parse line: ", splitLine);
				end
				readLine = fileStream:readLine();
			end
		else
			print("ISMiniHealth():: Failed to read config file...")
		end

		fileStream:close();
		print("ISMiniHealth(): Closed config file.")
	else
		print("ISMiniHealth(): Failed to open config file for reading...")
	end

	return failed;
end

function ISMiniHealth:writeConfig()
	local fileStream;
	fileStream = getFileWriter("Mini_health_conf.ini", true, false);

	if fileStream ~= nil then
		print("ISMiniHealth(): Opened config file for writing...")
		
		fileStream:write("CONFIG_VERSION="..tostring(self.CONFIG_VERSION).."\n");
		fileStream:write("pos_x="..tostring(self:getX()).."\n");
		fileStream:write("pos_y="..tostring(self:getY()).."\n");
		fileStream:write("alwaysShow="..tostring(self.alwaysShow).."\n");
		fileStream:write("showHpBar="..tostring(self.showHpBar).."\n");
		fileStream:write("showStrains="..tostring(self.showStrains).."\n");
		fileStream:write("moveWithMouse="..tostring(self.moveWithMouse).."\n");
		fileStream:write("latestNews="..tostring(self.latestNews).."\n");

		fileStream:close();
		print("ISMiniHealth(): Closed config file.")
	else
		print("ISMiniHealth(): Failed to open config file for writing...")
	end

end