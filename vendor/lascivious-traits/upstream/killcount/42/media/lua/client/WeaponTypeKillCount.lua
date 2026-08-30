
KillCountWeaponType = {}
KillCountWeaponType.Verbose = false

KillCountWeaponType.playerModDataUpdateFlags = {}

local lcl = {} 
lcl.hitCharacterMap = {}


lcl.getText        = getText
lcl.isClient       = isClient
lcl.getPlayer      = getPlayer
lcl.getTimestampMs = getTimestampMs



lcl.player_base          = __classmetatables[IsoPlayer.class].__index
lcl.player_isLocalPlayer = lcl.player_base.isLocalPlayer
lcl.player_getModData    = lcl.player_base.getModData

lcl.sm_base    = __classmetatables[ScriptManager.class].__index
lcl.sm_getItem = lcl.sm_base.getItem

lcl.item_base           = __classmetatables[zombie.scripting.objects.Item.class].__index
lcl.item_getDisplayName = lcl.item_base.getDisplayName

lcl.hw_base                = __classmetatables[HandWeapon.class].__index
lcl.hw_getWeaponCategories = lcl.hw_base.getWeaponCategories--B42.12.3-
lcl.hw_getPerk             = lcl.hw_base.getPerk--B42.13+
lcl.hw_getSubCategory      = lcl.hw_base.getSubCategory
lcl.hw_getType             = lcl.hw_base.getType
lcl.hw_isInstantExplosion  = lcl.hw_base.isInstantExplosion
lcl.hw_getExplosionRange   = lcl.hw_base.getExplosionRange


lcl.ArrayList_base        = __classmetatables[ArrayList.class].__index
lcl.ArrayList_size        = lcl.ArrayList_base.size
lcl.ArrayList_get         = lcl.ArrayList_base.get


function KillCountWeaponType.getWpnTypeDisplayName(weaponType)
    local scriptItem = lcl.sm_getItem(ScriptManager.instance,weaponType);
    if scriptItem then return lcl.item_getDisplayName(scriptItem) end--nominal
    return weaponType--backup
end

function KillCountWeaponType.getWpnCategoryDisplayName(weaponCategory)
    local defaultKey = "IGUI_perks_"..(weaponCategory or "")
    local translatedDefaultKey = lcl.getText(defaultKey)
    if translatedDefaultKey and translatedDefaultKey ~= defaultKey then return translatedDefaultKey end--return default key translation if it exists
    --if weaponCategory == "Blunt" then return lcl.getText("IGUI_perks_Blunt") end
    --if weaponCategory == "SmallBlunt" then return lcl.getText("IGUI_perks_SmallBlunt") end
    --if weaponCategory == "LongBlade" then return lcl.getText("IGUI_perks_LongBlade") end
    --if weaponCategory == "SmallBlade" then return lcl.getText("IGUI_perks_SmallBlade") end
    --if weaponCategory == "Axe" then return lcl.getText("IGUI_perks_Axe") end
    --if weaponCategory == "Spear" then return lcl.getText("IGUI_perks_Spear") end
    --if weaponCategory == "Firearm" then return lcl.getText("IGUI_perks_Firearm") end
    --handle special cases
    if weaponCategory == "Fire" then return lcl.getText("IGUI_Emote_Fire") end
    if weaponCategory == "Vehicles" then return lcl.getText("Sandbox_Vehicle") end
    if weaponCategory == "Unarmed" then return KillCountWeaponType.getWpnTypeDisplayName("BareHands") end
    if weaponCategory == "Explosives" then return lcl.getText("IGUI_ItemCat_Explosives") end
    --backup
    return lcl.getText(weaponCategory)
end

-- --tested OK in solo B42.13 game with unarmed / short blunt / short blade / long blunt / firearms
function KillCountWeaponType.GetWeaponCategoryFromWeapon(weapon)--if there is one category, return it. if there is more, return the first met that is not Improvised. if there is none, return SubCategory if valid else return "Other"
    local chosenCategory = "Other"

    local categories = Registries.WEAPON_CATEGORY:values()
    for i=0, categories:size()-1 do
        local wpnCat = categories:get(i)
        if weapon:isOfWeaponCategory(wpnCat) then
            chosenCategory = wpnCat:getTranslationName()
            if (chosenCategory ~= "Improvised") then return chosenCategory end
        end
    end

    if chosenCategory == "Other" or chosenCategory == "Improvised" then
        local subCategory = lcl.hw_getSubCategory(weapon)
        if subCategory and subCategory ~= "" then
            chosenCategory = subCategory;--range weapons use subcategory: Firearm
        end
    end
    return chosenCategory;
end

function KillCountWeaponType.GetWeaponTypeFromWeapon(weapon)
    return lcl.hw_getType(weapon)
end



function KillCountWeaponType.addToKillCount(wielder,victim,weapon,damage)
    if not wielder or not victim then return end
    if not (instanceof(wielder, "IsoPlayer") and lcl.player_isLocalPlayer(wielder)) then return end--MP Bombs & Bandits mod compat.

    local wielderModData = lcl.player_getModData(wielder)
    if wielderModData then
        if not wielderModData.KillCount then wielderModData.KillCount = {} end
        if weapon then
            local weaponCategory = KillCountWeaponType.GetWeaponCategoryFromWeapon(weapon)
            local weaponType = lcl.hw_getType(weapon)
            if weaponType and weaponCategory then
                if not wielderModData.KillCount.WeaponCategory then wielderModData.KillCount.WeaponCategory = {} end
                if not wielderModData.KillCount.WeaponCategory[weaponCategory] then wielderModData.KillCount.WeaponCategory[weaponCategory] = {count=0,WeaponType={}} end
                wielderModData.KillCount.WeaponCategory[weaponCategory].count = wielderModData.KillCount.WeaponCategory[weaponCategory].count + 1;
                if not wielderModData.KillCount.WeaponCategory[weaponCategory].WeaponType[weaponType] then wielderModData.KillCount.WeaponCategory[weaponCategory].WeaponType[weaponType] = 0 end
                wielderModData.KillCount.WeaponCategory[weaponCategory].WeaponType[weaponType] = wielderModData.KillCount.WeaponCategory[weaponCategory].WeaponType[weaponType] + 1;
                KillCountWeaponType.playerModDataUpdateFlags[wielder] = true
            end
            if KillCountWeaponType.Verbose and weaponType and weaponCategory then print ("KillCountWeaponType.addToKillCount "..tostring(weaponType or "nil").." "..tostring(wielderModData.KillCount.WeaponCategory[weaponCategory].WeaponType[weaponType] or "nil")..", "..tostring(weaponCategory or "nil").." "..tostring(wielderModData.KillCount.WeaponCategory[weaponCategory].count or "nil")) end
        end
    end
end

function KillCountWeaponType.OnHitZombie(zombie, wielder, bodyPart, weapon)
    --if KillCountWeaponType.Verbose then print ("KillCountWeaponType.OnHitZombie("..tostring(wielder or "nil")..", "..tostring(zombie or "nil")..", "..tostring(weapon or "nil")..", "..tostring(bodyPart or "nil")..")") end
    local hitLog = {}
    if KillCountWeaponType.Verbose and weapon and instanceof(weapon, "HandWeapon") then
        print ("KillCountWeaponType.OnHitZombie pipe bomb ? (",weapon:getCategory(),tostring(weapon:IsWeapon() and "IsWeapon" or "NotWeapon"),tostring(weapon:getPhysicsObject() or "nil"),tostring(weapon:getSubCategory() or "nil"),tostring(weapon:getPlacedSprite() or "nil"),tostring(weapon:getRunAnim() or "nil"),tostring(weapon:getStaticModel() or "nil"),tostring(weapon:getWeaponReloadType() or "nil"),tostring(weapon:getDamageCategory() or "nil"),tostring(weapon:getFireMode() or "nil"),tostring(weapon:isInstantExplosion() and "true" or "false"),")")
        print ("KillCountWeaponType.OnHitZombie explosion range (",tostring(weapon:getExplosionRange()),")")
    end
    if weapon and instanceof(weapon, "HandWeapon") and lcl.hw_getExplosionRange(weapon) > 0 and lcl.hw_isInstantExplosion(weapon) then
        hitLog.explosives = true
    end
    hitLog.wielder = wielder
    hitLog.weapon = weapon
    hitLog.timestampLastHit = lcl.getTimestampMs()
    lcl.hitCharacterMap[tostring(zombie:getID())] = hitLog;
end
Events.OnHitZombie.Add(KillCountWeaponType.OnHitZombie);

function KillCountWeaponType.isExplosiveDeath(victim)
    local hitLog = lcl.hitCharacterMap[tostring(victim:getID())]
    if KillCountWeaponType.Verbose and hitLog and hitLog.explosives then
        print ("KillCountWeaponType.isExplosiveDeath("..tostring(hitLog.weapon:getSubCategory() or "nil")..", "..tostring(hitLog.weapon:isInstantExplosion() and "true" or "false")..", "..tostring(hitLog.timestampLastHit or "nil")..", "..tostring(hitLog.timestampDead or "nil")..")")
    end
    
    return hitLog and not lcl.isClient() and hitLog.explosives and hitLog.timestampLastHit and (hitLog.timestampDead - hitLog.timestampLastHit < 100)--TODO put time threshold as config
end
function KillCountWeaponType.OnZombieDead(zombie,var2,var3,var4)
    local strVictim = tostring(zombie:getID())
    local hitLog = lcl.hitCharacterMap[strVictim]
    if hitLog then
        hitLog.onZombieDead = true
        hitLog.timestampDead = lcl.getTimestampMs()
        if KillCountWeaponType.isExplosiveDeath(zombie) then
            if KillCountWeaponType.Verbose then print ("KillCountWeaponType.OnZombieDead by explosive") end
        else
            if KillCountWeaponType.Verbose then print ("KillCountWeaponType.OnZombieDead NOT by explosive 1") end
        end
        if hitLog.wielder and hitLog.weapon then
        if KillCountWeaponType.Verbose then print ("KillCountWeaponType.OnZombieDead("..tostring(zombie or "nil")..", "..tostring(var2 or "nil")..", "..tostring(var3 or "nil")..", "..tostring(var4 or "nil")..")".." "..tostring(hitLog.wielder or "nil")) end
            KillCountWeaponType.addToKillCount(hitLog.wielder,zombie,hitLog.weapon,nil);
            lcl.hitCharacterMap[strVictim] = nil--lets not keep memory forever both for perf and because strVictim could be reused with a Z repop
        end
    else
        if KillCountWeaponType.Verbose then print ("KillCountWeaponType.OnZombieDead NOT by explosive 2") end
    end
    if KillCountWeaponType.Verbose then print ("KillCountWeaponType.OnZombieDead("..tostring(zombie or "nil")..", "..tostring(var2 or "nil")..", "..tostring(var3 or "nil")..", "..tostring(var4 or "nil")..")") end
end
Events.OnZombieDead.Add(KillCountWeaponType.OnZombieDead)

function KillCountWeaponType.OnWeaponHitCharacter(wielder,victim,weapon,damage)--wielder, target, weapon, damageSplit
    KillCountWeaponType.OnWeaponHitXp(wielder,weapon,victim,damage)
end
function KillCountWeaponType.OnWeaponHitXp(wielder,weapon,victim,damage)
    local strVictim = tostring(victim:getID())
    local hitLog = lcl.hitCharacterMap[strVictim]
    if hitLog then
        if wielder and hitLog.onZombieDead and instanceof(wielder, "IsoPlayer") and lcl.player_isLocalPlayer(wielder) then
            --weapon kill detected
            KillCountWeaponType.addToKillCount(wielder,victim,weapon,damage);
        end
        --clear hitLog
        lcl.hitCharacterMap[strVictim] = nil--lets not keep memory forever both for perf and because strVictim could be reused with a Z repop
    end

    if KillCountWeaponType.Verbose then print ("KillCountWeaponType.OnWeaponHitXp("..tostring(wielder or "nil")..", "..tostring(weapon or "nil")..", "..tostring(victim or "nil")..", "..tostring(damage or "nil")..")") end
end
--Events.OnWeaponHitXp.Add(KillCountWeaponType.OnWeaponHitXp);
--Events.OnWeaponHitCharacter.Add(KillCountWeaponType.OnWeaponHitCharacter);

--function KillCountWeaponType.OnThrowableExplode(throwable,sq)
--    if KillCountWeaponType.Verbose then print ("KillCountWeaponType.OnThrowableExplode("..tostring(throwable or "nil")..", "..tostring(sq or "nil")..")") end
--    local hitLog = {}
--    hitLog.wielder = wielder
--    hitLog.weapon = weapon
--    hitLog.damage = damage
--    hitLog.explosives = true
--    hitLog.timestampLastHit = lcl.getTimestampMs()
--    lcl.hitCharacterMap[tostring(zombie)] = hitLog;
--
--end
--
--Events.OnThrowableExplode.Add(KillCountWeaponType.OnThrowableExplode)


--Sync player mod data in MP
if isClient() then
function KillCountWeaponType.synchronizePlayersModData()--local players
    local toRemovePlayers = {}
    for wielder, flag in pairs(KillCountWeaponType.playerModDataUpdateFlags) do
        if flag then
            wielder:transmitModData()
            table.insert(toRemovePlayers,wielder)
        end
    end
    for iter, wielder in ipairs(toRemovePlayers) do
        KillCountWeaponType.playerModDataUpdateFlags[wielder] = nil
    end
end
Events.OnTick.Add(KillCountWeaponType.synchronizePlayersModData)
end
