if getCore():isDedicated() then return; end

require ('XpSystem/ISUI/ISCharacterScreen')


local rescaleHeight = false --deactivate this as it has low compatibility
local banditOffsetActive = false
local modInfoBandits = getModInfoByID("Bandits")
if modInfoBandits and isModActive(modInfoBandits) then
--compatibility they go first
require ('ISUI/BanditCharacterScren')
rescaleHeight = false
banditOffsetActive = true
end


local lcl = {}
lcl.player_base           = __classmetatables[IsoPlayer.class].__index
lcl.player_getModData     = lcl.player_base.getModData
lcl.player_getZombieKills = lcl.player_base.getZombieKills

lcl.tm_base            = __classmetatables[TextManager.class].__index
lcl.tm_MeasureStringX  = lcl.tm_base.MeasureStringX


lcl.ui_base  = __classmetatables[UIElement.class].__index
lcl.drawText = lcl.ui_base.DrawText

lcl.getPlayer = getPlayer
lcl.getText   = getText

local hookedZValue = 0;
local genuineZValue = 0;
local upperLayer_setHeightAndParentHeight = nil;
function hooked_ISUIElement_setHeightAndParentHeight(ownInstance,z)
    local smallFontHgt = getTextManager():getFontFromEnum(UIFont.Small):getLineHeight();
    genuineZValue = z;
    --print( "hooked_ISUIElement_setHeightAndParentHeight "..z );
    local botDist = (smallFontHgt+6) * 2 + 10
    if z > botDist then
        hookedZValue = z - botDist;
        if banditOffsetActive then
            local clock = UIManager.getClock()
            if clock and clock:isDateVisible() then
                hookedZValue = hookedZValue - getTextManager():getFontFromEnum(UIFont.Small):getLineHeight();
            end
        end
    end
    if not rescaleHeight then
        upperLayer_setHeightAndParentHeight(ownInstance,z)
    end
end

local genuine_ISCharacterScreen_render = ISCharacterScreen.render
function ISCharacterScreen:render()
    local genuine_ISUIElement_setHeightAndParentHeight = ISUIElement.setHeightAndParentHeight;--prepare unhooking of the height function
    local player = self.char or lcl.getPlayer();
    local md = lcl.player_getModData(player).AKCModData
    if not self.javaObject then md = nil end
    
    if md ~= nil then 
        upperLayer_setHeightAndParentHeight = genuine_ISUIElement_setHeightAndParentHeight
        ISUIElement.setHeightAndParentHeight = hooked_ISUIElement_setHeightAndParentHeight;--hook the height function
    end

    genuine_ISCharacterScreen_render(self);--call genuine render with possibly hooked height function

    if md ~= nil then
        if hookedZValue ~= 0 then
            local weaponKill = lcl.player_getZombieKills(player);
            local fireKill = (md.fk or 0);
            local totalKill = weaponKill + fireKill;
            local textManager = getTextManager()
            local textWid1 = lcl.tm_MeasureStringX(textManager, UIFont.Small, lcl.getText("IGUI_char_Favourite_Weapon"))
            local textWid2 = lcl.tm_MeasureStringX(textManager, UIFont.Small, lcl.getText("IGUI_char_Zombies_Killed"))
            local textWid3 = lcl.tm_MeasureStringX(textManager, UIFont.Small, lcl.getText("IGUI_char_Survived_For"))
            local x = 20 + math.max(textWid1, math.max(textWid2, textWid3)) + lcl.tm_MeasureStringX(textManager, UIFont.Small, ""..weaponKill)--retrieve x value the way PZ does it. add the x offset for current "weapon kill"
            
            local txtWpn  = lcl.getText("UI_KillCount_weapon");
            local txtFire = lcl.getText("UI_KillCount_fire");
            local addedText = "("..txtWpn..") + "..fireKill.."("..txtFire..") = " .. totalKill
            lcl.drawText(self.javaObject, UIFont.Small, addedText, x + 10, hookedZValue, 1, 1, 1, 0.5)--add text with corrected kill numbers
        end
        
        ISUIElement.setHeightAndParentHeight = genuine_ISUIElement_setHeightAndParentHeight;--unhook the height function
        
        if rescaleHeight then--if not bandit or other height setting mods
            self:setHeightAndParentHeight(genuineZValue);--call the real function, hope for genuineZ being valid
        end
    end
end
