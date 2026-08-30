require "ISUI/ISPanelJoypad"
require "WeaponTypeKillCount"
require "ISCharacterInfoWindow_AddTab"


local lcl = {} 

lcl.player_base           = __classmetatables[IsoPlayer.class].__index
lcl.player_getModData     = lcl.player_base.getModData
lcl.player_getZombieKills = lcl.player_base.getZombieKills
lcl.player_getUsername    = lcl.player_base.getUsername


lcl.tm_base            = __classmetatables[TextManager.class].__index
lcl.tm_getFontHeight  = lcl.tm_base.getFontHeight
lcl.tm_MeasureStringX  = lcl.tm_base.MeasureStringX


lcl.ui_base  = __classmetatables[UIElement.class].__index
lcl.drawText = lcl.ui_base.DrawText

lcl.getText = getText
--UIElement

ISCharacterKills = ISPanelJoypad:derive("ISCharacterKills");

function ISCharacterKills:initialise()
    ISPanelJoypad.initialise(self);
end

function ISCharacterKills:createChildren()
    local tickBox = ISTickBox:new(0, 0, 10, 10, "", self, ISCharacterKills.onShowDeadChange)
    tickBox:initialise()
    self:addChild(tickBox)
    tickBox:addOption("")
    self.showDeadTickBox = tickBox
    tickBox.tooltip = getText("UI_KCIncludeDead")


    self:setScrollChildren(true)
    self:addScrollBars()
end

function ISCharacterKills:setVisible(visible)
    self.javaObject:setVisible(visible);
end

function ISCharacterKills:prerender()
    ISPanelJoypad.prerender(self)
    self:setStencilRect(0, 0, self.width, self.height)
end

function ISCharacterKills:render()
    local ktd = SandboxVars.KillCount.keepTrackOfDead and SandboxVars.KillCount.shareOnServer
    self.showDeadTickBox:setVisible(ktd)
    if not ktd then
        self.showDead = false
    end

    local killCountModData = nil
    local md = lcl.player_getModData(self.char)
    if md and self.javaObject then
        if not self.comboButton then
            self:onPlayersKillsUpdate()
        end
        
        local selectedPlayer = nil
        local playerArray = nil
        if self.showDead then
            selectedPlayer = self.selectedPlayer
            playerArray = self.playerArray
        else
            selectedPlayer = self.selectedPlayerNoDead
            playerArray = self.playerArrayNoDead
        end
        if self.comboButton then self.comboButton:setVisible(self.showDead or false) end
        if self.comboButtonNoDead then self.comboButtonNoDead:setVisible(not self.showDead) end
        
        if not selectedPlayer or selectedPlayer <= 1 then
            killCountModData = md.KillCount
        else
            local playerName = playerArray[selectedPlayer]
            local gmd = KCShared.getModData()
            if gmd then
                killCountModData = gmd[playerName]
            end
       end
    end
    ------------------------------------
    local textManager = getTextManager()
    local smallFont = UIFont.Small
    
    local textX = self.categoryXOffset
    local fontHeight = lcl.tm_getFontHeight(textManager, smallFont)
    
    if self.playerArray and #self.playerArray >= 1 then
        local preText = lcl.getText("UI_KCComboTitle")
        self:drawText(preText, textX, fontHeight, 1, 1, 1, 1, UIFont.Medium)
    end
    
    if not killCountModData or not killCountModData.WeaponCategory then
        self:hideButtons()
        killCountModData = {WeaponCategory={}}--replace with a fake empty
    end
    ------------------------------------
   
    local textY = fontHeight
    if self.playerArray and #self.playerArray >= 1 then
        textY = textY + (self.comboHeight or 0)
    else
        if self.comboButton then
            self.comboButton:setVisible(false)
        end
        if self.comboButtonNoDead then
            self.comboButtonNoDead:setVisible(false)
        end
    end
    local maxTextWidth = 0
    local iterCategories = 0
    local total = 0
    for category,struct in pairs(killCountModData.WeaponCategory) do
        iterCategories = iterCategories + 1;
        local displayCategoryWeapons = self:displayCategoryWeapons(iterCategories)
        local expandChar = "+ "
        local xButtonOffset = 7
        if displayCategoryWeapons then expandChar = "- "; xButtonOffset = 5 end
        local catText = expandChar .. KillCountWeaponType.getWpnCategoryDisplayName(category) .. " " .. struct.count
        total = total + (struct.count or 0)
        local button = self:getCategoryButton(iterCategories);--potentially instanciate
        button:setX(textX-xButtonOffset);
        button:setY(textY);
        button:setWidthToTitle();
        button:setTitle(catText)
        button.enable = true;
        button:setVisible(true);
        local textWidth = lcl.tm_MeasureStringX(textManager, smallFont, catText);
        if textWidth > maxTextWidth then maxTextWidth = textWidth end
        textY = textY + fontHeight
        if displayCategoryWeapons then--todo use buttons for categories
            for weaponType,count in pairs(struct.WeaponType) do
                local wpnText = "-  ".. KillCountWeaponType.getWpnTypeDisplayName(weaponType) .. " " .. count
                lcl.drawText(self.javaObject, smallFont, wpnText, textX, textY, 0.7, 0.7, 0.7, 1)
                local wpnWidth = lcl.tm_MeasureStringX(textManager, smallFont, wpnText);
                if wpnWidth > maxTextWidth then maxTextWidth = wpnWidth end
                textY = textY + fontHeight
            end
        end
    end
    
    if md.AKCModData and killCountModData == md.KillCount then
        --add explosives kills
        if md.AKCModData.ek and md.AKCModData.ek > 0 then
            local catText = "- ".. KillCountWeaponType.getWpnCategoryDisplayName("Explosives") .. " " .. md.AKCModData.ek;
            lcl.drawText(self.javaObject, smallFont, catText, textX, textY, 1, 1, 1, 1)
            local wpnWidth = lcl.tm_MeasureStringX(textManager, smallFont, catText);
            if wpnWidth > maxTextWidth then maxTextWidth = wpnWidth end
            textY = textY + fontHeight
            total = total + md.AKCModData.ek
        end

        --add fire kills
        if md.AKCModData.fk and md.AKCModData.fk > 0 then
            local catText = "- ".. KillCountWeaponType.getWpnCategoryDisplayName("Fire") .. " " .. md.AKCModData.fk;
            lcl.drawText(self.javaObject, smallFont, catText, textX, textY, 1, 1, 1, 1)
            local wpnWidth = lcl.tm_MeasureStringX(textManager, smallFont, catText);
            if wpnWidth > maxTextWidth then maxTextWidth = wpnWidth end
            textY = textY + fontHeight
            total = total + md.AKCModData.fk
        end

        --add car kills
        if md.AKCModData.ck and md.AKCModData.ck > 0 then
            local catText = "- ".. KillCountWeaponType.getWpnCategoryDisplayName("Vehicles") .. " " .. md.AKCModData.ck;
            lcl.drawText(self.javaObject, smallFont, catText, textX, textY, 1, 1, 1, 1)
            local wpnWidth = lcl.tm_MeasureStringX(textManager, smallFont, catText);
            if wpnWidth > maxTextWidth then maxTextWidth = wpnWidth end
            textY = textY + fontHeight
            total = total + md.AKCModData.ck
        end
    end
    textY = textY + fontHeight
    local totalText = lcl.getText("IGUI_char_Zombies_Killed") .. " " .. total
    lcl.drawText(self.javaObject, smallFont, totalText, textX, textY, 1, 1, 1, 1)
    textY = textY + fontHeight
    
    if self.playerArray and #self.playerArray > 1 and SandboxVars.KillCount.shareOnServer then
        totalText = lcl.getText('UI_chat_server_chat_title_id')..' '..lcl.getText('IGUI_char_Zombies_Killed') .. " " .. (self.serverTotalKills or 0)
        lcl.drawText(self.javaObject, smallFont, totalText, textX, textY, 1, 1, 1, 1)
        textY = textY + fontHeight
    end
    
    
    textY = textY + fontHeight--more satisfying with an empty line

    local widthRequired = textX * 2 + maxTextWidth
    if widthRequired > self:getWidth() then
        self:setWidthAndParentWidth(widthRequired);
    end
    local tabHeight = self.y
    local maxHeight = getCore():getScreenHeight() - tabHeight - 20
    if ISWindow and ISWindow.TitleBarHeight then maxHeight = maxHeight - ISWindow.TitleBarHeight end
    
    self:setHeightAndParentHeight(math.min(textY, maxHeight));
    self:setScrollHeight(textY)
    
    self:clearStencilRect()
end

function ISCharacterKills:onMouseWheel(del)
    self:setYScroll(self:getYScroll() - del * 30)
    return true
end

function ISCharacterKills:new (x, y, width, height, playerNum)
    local o = {};
    o = ISPanelJoypad:new(x, y, width, height);
    setmetatable(o, self);
    self.__index = self;
    o.playerNum = playerNum
    o.char = getSpecificPlayer(playerNum);
    o:noBackground();
    o.categoryButtons = {}
    o.categoryXOffset = 20
    --prebuild some weapon category buttons
    o:getCategoryButton(10)
    o.selectedPlayer = 1
    o.selectedPlayerNoDead = 1
    
    ISCharacterKills.instance = o;
    return o;
end

function ISCharacterKills:displayCategoryWeapons(iter)
    if iter > #self.categoryButtons then return false end
    return self.categoryButtons[iter].displayWeapons
end
function ISCharacterKills:onClickCategory(button, iter)
    self:getCategoryButton(iter);
    self.categoryButtons[iter].displayWeapons = not self.categoryButtons[iter].displayWeapons
    if KillCountWeaponType.Verbose then print ("ISCharacterKills.onClickCategory("..tostring(iter or "nil").." = "..tostring(self.categoryButtons[iter].displayWeapons and "true" or "false")..")") end
end

function ISCharacterKills:hideButtons()
    for it=1, #self.categoryButtons do
        self.categoryButtons[it].button:setVisible(false)
    end
end

function ISCharacterKills:getCategoryButton(iter)
    if not self.categoryButtons then self.categoryButtons = {} end
    while iter > #self.categoryButtons do
        local newIter = #self.categoryButtons + 1
        local fontHeight = getTextManager():getFontHeight(UIFont.Small)
        local newButton = ISButton:new(0,0, 1, fontHeight, " ", self, ISCharacterKills.onClickCategory);--args?
        newButton:setOnClick(ISCharacterKills.onClickCategory, newIter)--add args after target on button click
        newButton:initialise();
        newButton:instantiate();
        newButton:setVisible(false);
        newButton:setBackgroundRGBA(0,0,0,0);
        newButton:setBackgroundColorMouseOverRGBA(0.3, 0.3, 0.3, 0.5);
        newButton:setBorderRGBA(0,0,0,0);
        
        self.categoryButtons[newIter] = {}
        self.categoryButtons[newIter].button = newButton
        self.categoryButtons[newIter].displayWeapons = false
        self:addChild(self.categoryButtons[newIter].button);
        if KillCountWeaponType.Verbose then print ("ISCharacterKills:create category button "..newIter); end
    end
    return self.categoryButtons[iter].button
end

function ISCharacterKills:ensureVisible()
    if not self.joyfocus then return end
    local child = nil;--TODO manage scroll? self.progressBars[self.joypadIndex]
    if not child then return end
    local y = child:getY()
    if y - 40 < 0 - self:getYScroll() then
        self:setYScroll(0 - y + 40)
    elseif y + child:getHeight() + 40 > 0 - self:getYScroll() + self:getHeight() then
        self:setYScroll(0 - (y + child:getHeight() + 40 - self:getHeight()))
    end
end

function ISCharacterKills:onGainJoypadFocus(joypadData)
    ISPanelJoypad.onGainJoypadFocus(self, joypadData);
    self.joypadIndex = nil
    self.barWithTooltip = nil
end

function ISCharacterKills:onLoseJoypadFocus(joypadData)
    ISPanelJoypad.onLoseJoypadFocus(self, joypadData);
end

function ISCharacterKills:onJoypadDown(button)
    if button == Joypad.AButton then
    end
    if button == Joypad.YButton then
    end
    if button == Joypad.BButton then
    end
    if button == Joypad.LBumper then
        getPlayerInfoPanel(self.playerNum):onJoypadDown(button)
    end
    if button == Joypad.RBumper then
        getPlayerInfoPanel(self.playerNum):onJoypadDown(button)
    end
end

function ISCharacterKills:onJoypadDirDown()
    self.joypadIndex = self.joypadIndex + 1
    self:ensureVisible()
    self:updateTooltipForJoypad()
end

function ISCharacterKills:onJoypadDirLeft()
end

function ISCharacterKills:onJoypadDirRight()
end

local function addComboOption(combo,txt,previousWidth)
    local txtWidth = getTextManager():MeasureStringX(UIFont.Small, txt);
    combo:addOption(txt)
    if previousWidth > txtWidth then return previousWidth end
    return txtWidth
end

function ISCharacterKills:onComboSelect()
    self.selectedPlayer = self.comboButton.selected
    self:hideButtons()
end

function ISCharacterKills:onComboNoDeadSelect()
    self.selectedPlayerNoDead = self.comboButtonNoDead.selected
    self:hideButtons()
end

function ISCharacterKills:onShowDeadChange(index, selected)
    self.showDead = selected
end

function ISCharacterKills:onPlayersKillsUpdate()
    self:createComboButton()
    self.serverTotalKills = self:computeServerKills()
end

function ISCharacterKills:computeServerKills()
    local totalKill = lcl.player_getZombieKills(self.char)
    local gmd = KCShared.getModData()
    if not gmd then return end--not ready yet
    local myName = lcl.player_getUsername(self.char)
    for userName,data in pairs(gmd) do
        if userName ~= myName then--then all others
            for category,struct in pairs(data.WeaponCategory) do
                totalKill = totalKill + (struct.count or 0)
            end
        end
    end
    return totalKill
end

function ISCharacterKills:createComboButton()
    if not SandboxVars.KillCount.shareOnServer then return end
    local gmd = KCShared.getModData()
    if not gmd then return end--not ready yet
    
    local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
    local comboOffset = 3 * 2
    local comboHeight = FONT_HGT_MEDIUM + comboOffset
    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    local textX = self.categoryXOffset
    local textY = fontHeight
    
    local preText = lcl.getText("UI_KCComboTitle")
    local preTextWidth = getTextManager():MeasureStringX(UIFont.Medium, preText);
    
    local combo       = ISComboBox:new(textX+preTextWidth, fontHeight-comboOffset, 10, comboHeight, self, self.onComboSelect)
    local comboNoDead = ISComboBox:new(textX+preTextWidth, fontHeight-comboOffset, 10, comboHeight, self, self.onComboNoDeadSelect)
    --combo.noSelectionText = "Select Cook Mode"
    self.playerArray = {}--reset
    self.playerArrayNoDead = {}--reset
    local myName = lcl.player_getUsername(self.char)
    local width       = addComboOption(combo      ,myName,0)--start with us
    local widthNoDead = addComboOption(comboNoDead,myName,0)--start with us
    local nbNoDead = 1
    table.insert(self.playerArray      ,myName)
    table.insert(self.playerArrayNoDead,myName)
    for userName,data in pairs(gmd) do
        if userName ~= myName then--then all others
            width = addComboOption(combo,userName,width)
            table.insert(self.playerArray,userName)
            if not string.find(userName,'%.') then
                widthNoDead = addComboOption(comboNoDead,userName,widthNoDead)
                table.insert(self.playerArrayNoDead,userName)
            end
        end
    end
    if self.selectedPlayer > #self.playerArray then self.selectedPlayer = 1 end--error, fallback to self
    combo:setWidth(width+30)
    if self.comboButton then self:removeChild(self.comboButton) end
    if self.selectedPlayer then combo.selected = self.selectedPlayer end--keep selection iterator on update
    self:addChild(combo)
    self.comboButton = combo
    self.comboHeight = combo:getBottom()
    

    if self.selectedPlayerNoDead > #self.playerArrayNoDead then self.selectedPlayerNoDead = 1 end--error, fallback to self
    comboNoDead:setWidth(width+30)
    if self.comboButtonNoDead then self:removeChild(self.comboButtonNoDead) end
    if self.selectedPlayerNoDead then comboNoDead.selected = self.selectedPlayerNoDead end--keep selection iterator on update
    self:addChild(comboNoDead)
    self.comboButtonNoDead = comboNoDead
    
    self.showDeadTickBox:setX(self.comboButton:getRight()+10)
    self.showDeadTickBox:setY(fontHeight-comboOffset)
    self.showDeadTickBox:setWidth(comboHeight)
    self.showDeadTickBox:setHeight(comboHeight)
    self.showDeadTickBox:setVisible(true)
end


addCharacterPageTab("Kills",ISCharacterKills)
