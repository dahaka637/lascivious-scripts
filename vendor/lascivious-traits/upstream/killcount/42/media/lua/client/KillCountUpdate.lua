
--print ("KillCount isDedicated="..tostring(getCore():isDedicated() and "true" or "false"))--true probably only for multiplayer dedicated server for server and shared lua modules
--print ("KillCount isClient="..tostring(isClient() and "true" or "false"))--true in multiplayer as client or host
--print ("KillCount isServer="..tostring(isServer() and "true" or "false"))--true ??

--this.setAttackedBy((IsoGameCharacter)null); <= this is done just before Zombie dead by Fire


if getCore() and getCore():isDedicated() then return; end

require ('WeaponTypeKillCount')--ensure WeaponTypeKillCount OnZombieDead callback is registered before KillCountUpdate

KillCount = KillCount or {}
KillCount.DELAY_MAX_SAME_KILL = 20000;--20s max for same kill, this should allows any realistic Z respawn speed AND not bother too much my/any future resurrection mods AND eat any freeze. priority to freeze for now.
KillCount.DELAY_MAX_WEAPON_HIT = 5000;--5s max 
KillCount.Verbose = false;


local lcl = {}
lcl.player_base          = __classmetatables[IsoPlayer.class].__index
lcl.player_getModData    = lcl.player_base.getModData
lcl.player_getVehicle    = lcl.player_base.getVehicle
lcl.player_isLocalPlayer = lcl.player_base.isLocalPlayer

lcl.getTimestampMs = getTimestampMs
lcl.getPlayer = getPlayer


function KillCount.initVersionId()
    local ver_str = getCore():getVersionNumber()
    local num1, num2 = ver_str:match("(%d+)%.(%d+)")
    KillCount.num1 = tonumber(num1)
    KillCount.num2 = tonumber(num2)
end
KillCount.initVersionId()

function KillCount.isB41_60Plus()
    return (KillCount.num1>41 or KillCount.num1==41 and KillCount.num2>=60);
end
function KillCount.isB41_50()
    return (KillCount.num1<41 or KillCount.num1==41 and KillCount.num2<=50);
end


function KillCount.createModData(player)
    if not player or not lcl.player_isLocalPlayer(player) then return end
    local md = lcl.player_getModData(player)
    if md.AKCModData == nil then
        md.AKCModData = {};
        local nbkill = player:getZombieKills() or 0;
        md.AKCModData.gk  = nbkill;
        md.AKCModData.fk  = 0;
        md.AKCModData.ck  = 0;
    else
        if md.AKCModData.ck == nil then
            --backward compatibility for saves before v 1.2
            md.AKCModData.fk  = 0;
            md.AKCModData.ck  = nbkill-md.AKCModData.gk;
            md.AKCModData.gk  = nbkill;
        end
    end
end

function KillCount.debugTable(zombieTableForKillCount)
    if not KillCount.Verbose then return end
    local iter = 1
    for key,value in pairs(zombieTableForKillCount) do 
        print ("Debug Table "..iter..": ["..key.."] "..value);--
        iter = iter + 1;
    end
    if iter == 1 then
        print ("Debug Table (empty)");
    end

end

function KillCount.clearTableOldMemories(myTable,myCurrentTime,maxTime)
    if not myTable then return end
    local keysToRemove = {}
    for key,val in pairs(myTable) do
        if myCurrentTime-val > maxTime then
            table.insert(keysToRemove,key)
        end
    end
    
    for it=1, #keysToRemove do
        key = keysToRemove[it]
        myTable[key] = nil
        if KillCount.Verbose then print('KillCount.clearTableOldMemories removed key '..key) end
    end

    return myTable
end

function KillCount.clearOldMemories()
    local currentTime = lcl.getTimestampMs()
    weaponTableForKillCount = KillCount.clearTableOldMemories(weaponTableForKillCount,currentTime,KillCount.DELAY_MAX_WEAPON_HIT)
    characterTableForKillCount = KillCount.clearTableOldMemories(characterTableForKillCount,currentTime,KillCount.DELAY_MAX_SAME_KILL)
    zombieTableForKillCount = KillCount.clearTableOldMemories(zombieTableForKillCount,currentTime,KillCount.DELAY_MAX_SAME_KILL)
    zombieTable2ForKillCount = KillCount.clearTableOldMemories(zombieTable2ForKillCount,currentTime,KillCount.DELAY_MAX_SAME_KILL)
    zombieTableForCarKillCount = KillCount.clearTableOldMemories(zombieTableForCarKillCount,currentTime,KillCount.DELAY_MAX_SAME_KILL)
    zombieTableForExplosionKillCount = KillCount.clearTableOldMemories(zombieTableForExplosionKillCount,currentTime,KillCount.DELAY_MAX_SAME_KILL)
end

function KillCount.updateB41_52_OnCharacterDeath(character)
    local player = lcl.getPlayer();
    if not player or not lcl.player_isLocalPlayer(player) then return end
    KillCount.createModData(player);
    local charStr = tostring(character);
    if charStr == tostring(player) then return; end
    KillCount.clearOldMemories()
    --first call on characterDeath we count it as car kill
    if zombieTable2ForKillCount and zombieTable2ForKillCount[charStr] ~= nil then--Fire Kill
        if KillCount.Verbose then print('KillCount.updateB41_52_OnCharacterDeath increase fire kill.') end
        lcl.player_getModData(player).AKCModData.fk = lcl.player_getModData(player).AKCModData.fk + 1;
        zombieTable2ForKillCount[charStr] = nil;
        zombieTableForKillCount[charStr] = nil;
        KillCount.debugTable(zombieTable2ForKillCount);
        KillCount.debugTable(zombieTableForKillCount);
    else--car kill (unless it is a weapon kill)
        if weaponTableForKillCount and weaponTableForKillCount[charStr] ~= nil then
            if KillCount.Verbose then print('KillCount.updateB41_52_OnCharacterDeath after weapon kill ignore it. '..charStr..' '..tostring(player:getVehicle() or 'no vehicle')) end
            weaponTableForKillCount[charStr] = nil;
            KillCount.debugTable(weaponTableForKillCount);
        elseif zombieTableForKillCount and zombieTableForKillCount[charStr] ~= nil then--Car Kill or Explosion kill
            if (not KillCountWeaponType or not KillCountWeaponType.isExplosiveDeath or not KillCountWeaponType.isExplosiveDeath(character)) then
                if KillCount.Verbose then print('KillCount.updateB41_52_OnCharacterDeath increase car kill. '..tostring(player:getVehicle() or 'no vehicle')) end
                --TODO count only if there is no recent OnWeaponHitXp on that Zombie and if the player is in a vehicle
                local vehicle = lcl.player_getVehicle(player)
                if vehicle and vehicle:getDriver() == player then
                    lcl.player_getModData(player).AKCModData.ck = lcl.player_getModData(player).AKCModData.ck + 1;
                    zombieTableForCarKillCount[charStr] = zombieTableForKillCount[charStr]
                end
            else
                if KillCount.Verbose then print('KillCount.updateB41_52_OnCharacterDeath increase explosion kill.') end
                lcl.player_getModData(player).AKCModData.ek = (lcl.player_getModData(player).AKCModData.ek or 0) + 1;
                zombieTableForExplosionKillCount[charStr] = zombieTableForKillCount[charStr]
            end
            --KillCount.debugTable(zombieTableForKillCount);
            zombieTableForKillCount[charStr] = nil;
        else--it is probably a weapon kill, we wil detect it on ZombieDead but let the genuine counter work anyway
            characterTableForKillCount[charStr] = lcl.getTimestampMs();
        end
    end
end

function KillCount.updateB41_52_OnZombieDead(character)
    local player = lcl.getPlayer();
    if not player or not lcl.player_isLocalPlayer(player) then return end
    KillCount.createModData(player);
    local charStr = tostring(character);
    if charStr == tostring(player) then return; end
    KillCount.clearOldMemories()
    if characterTableForKillCount and characterTableForKillCount[charStr] ~= nil then--Wpn Kill (Character
        if KillCount.Verbose then print('KillCount.updateB41_52_OnZombieDead increase weapon kill 1. '..tostring(player:getVehicle() or 'no vehicle')) end
        lcl.player_getModData(player).AKCModData.gk = (lcl.player_getModData(player).AKCModData.gk or 0) + 1 --wpn kill are just counted for future use, for now we stick on genuine counter for display
        characterTableForKillCount[charStr] = nil;
        KillCount.debugTable(characterTableForKillCount);
    elseif weaponTableForKillCount and weaponTableForKillCount[charStr] ~= nil then
        if KillCount.Verbose then print('KillCount.updateB41_52_OnZombieDead increase weapon kill 2. '..tostring(player:getVehicle() or 'no vehicle')) end
        lcl.player_getModData(player).AKCModData.gk = (lcl.player_getModData(player).AKCModData.gk or 0) + 1 --wpn kill are just counted for future use, for now we stick on genuine counter for display
        KillCount.debugTable(weaponTableForKillCount);
    else--it is Fire Kill or Car Kill let OnCharacterDeath decide
        if zombieTableForKillCount and zombieTableForKillCount[charStr] ~= nil then--
            zombieTable2ForKillCount[charStr] = lcl.getTimestampMs();--Fire Kill
        else
            zombieTableForKillCount[charStr] = lcl.getTimestampMs();--Car Kill or Fire Kill
        end
    end
end

function KillCount.updateB41_60_OnZombieDead(character)
    local player = lcl.getPlayer();
    if not player or not lcl.player_isLocalPlayer(player) then return end
    KillCount.clearOldMemories()
    local charStr = tostring(character);
    local timestamp = lcl.getTimestampMs()
    local consumedChar = false
    if zombieTableForKillCount and zombieTableForKillCount[charStr] ~= nil and timestamp - zombieTableForKillCount[charStr] < KillCount.DELAY_MAX_SAME_KILL then--we already counted a OnZombieDead for that Z
        --if it is recent, it means it is a fire kill. (only fire kills are sources for twice OnZombieDead in short period of time
        KillCount.createModData(player);
        local md = lcl.player_getModData(player).AKCModData
        if KillCount.Verbose then print('KillCount.updateB41_60_OnZombieDead increase fire kill. '..tostring(player:getVehicle() or 'no vehicle')) end
        md.fk = md.fk + 1;--we count ALL fire kills as ours. It is stupid, but I have no better
        if zombieTableForCarKillCount and zombieTableForCarKillCount[charStr] ~= nil then
            if timestamp - zombieTableForCarKillCount[charStr] < KillCount.DELAY_MAX_SAME_KILL then
                --We fire-killed a Z while in a car: rollback on car kill
                if KillCount.Verbose then print('KillCount.updateB41_60_OnZombieDead decrease car kill. '..tostring(player:getVehicle() or 'no vehicle')) end
                md.ck = md.ck - 1;
            end
            zombieTableForCarKillCount[charStr] = nil;
        end
        zombieTableForKillCount[charStr] = nil;
        consumedChar = true
    elseif character:getActionStateName() == "onground" then
        local vehicle = nil
        local target = character:getTarget()
        if target and instanceof(target, "IsoGameCharacter") then
            vehicle = lcl.player_getVehicle(target)
        end
        if vehicle and vehicle:getDriver() == player then 
            --for now we need the target of the Z to be onboard of the car for car kill detection. So the case of a car driver saving a poor survivor on feet by driving on its aggressor may not be managed (to be tested)
            KillCount.createModData(player);
            local md = lcl.player_getModData(player).AKCModData
            --print("print_OnZombieDead Vehicle ".. tostring(character)..getStrParam(character:getTarget():getVehicle()));
            if KillCount.Verbose then print('KillCount.updateB41_60_OnZombieDead increase car kill. '..tostring(vehicle or 'no vehicle')) end
            md.ck = md.ck + 1;
            zombieTableForCarKillCount[charStr] = timestamp
        end
    end
    
    if not consumedChar then
        zombieTableForKillCount[charStr] = timestamp
    end
end

function KillCount.updateB41_60_OnWeaponHitXp(character, weapon, characterTarget, damage)
    KillCount.clearOldMemories()
    local charStr = tostring(characterTarget);
    local removedErrorKill = false
    if zombieTableForCarKillCount then
        local previousCarKillTime = zombieTableForCarKillCount[charStr]
        if previousCarKillTime then
            local player = lcl.getPlayer();
            if not player or not lcl.player_isLocalPlayer(player) then return end
            --We (range?-)weapon-killed a Z while in a car: rollback on car kill
            if KillCount.Verbose then print('KillCount.updateB41_60_OnWeaponHitXp decrease car kill. '..tostring(player:getVehicle() or 'no vehicle')) end
            local md = lcl.player_getModData(player).AKCModData
            md.ck = md.ck - 1;
            removedErrorKill = true
            zombieTableForCarKillCount[charStr] = nil;
        end
    end

    if zombieTableForExplosionKillCount then
        local previousExplosionKillTime = zombieTableForExplosionKillCount[charStr]
        if previousExplosionKillTime then
            local player = lcl.getPlayer();
            if not player or not lcl.player_isLocalPlayer(player) then return end
            --We (range?-)weapon-killed a Z while explosing it: rollback on explosion kill
            if KillCount.Verbose then print('KillCount.updateB41_60_OnWeaponHitXp decrease explosion kill. '..tostring(player:getVehicle() or 'no vehicle')) end
            local md = lcl.player_getModData(player).AKCModData
            md.ek = (md.ek or 1) - 1;
            removedErrorKill = true
            zombieTableForExplosionKillCount[charStr] = nil;
        end
    end
    
    if not removedErrorKill then--it is an exhausted spear kill: prepare memory
        weaponTableForKillCount[charStr] = lcl.getTimestampMs();--Weapon kill memory
    end
end

function KillCount.updateB42_15_OnWeaponHitCharacter(character, characterTarget, weapon, damage)--wielder, target, weapon, damageSplit
    KillCount.updateB41_60_OnWeaponHitXp(character, weapon, characterTarget, damage)
end

if not isClient() then
    weaponTableForKillCount = {};
    characterTableForKillCount = {};
    zombieTableForKillCount = {};
    zombieTable2ForKillCount = {};
    zombieTableForCarKillCount = {};
    zombieTableForExplosionKillCount = {};
    Events.OnCharacterDeath.Add(KillCount.updateB41_52_OnCharacterDeath);
    Events.OnZombieDead.Add(KillCount.updateB41_52_OnZombieDead);
    Events.OnWeaponHitXp.Add(KillCount.updateB41_60_OnWeaponHitXp);
    Events.OnWeaponHitCharacter.Add(KillCount.updateB42_15_OnWeaponHitCharacter);
    --Events.OnTick.Add(KillCount.computeKillNumbers);
end

Events.OnGameStart.Add(KillCount.createModData);
Events.OnLoad.Add(KillCount.createModData);


local function getStrParam(param)
    return " "..tostring(param or "nil")
end

local function print_OnCharacterDeath(character, param2, param3, param4, param5)
    print("print_OnCharacterDeath".. getStrParam(character)..getStrParam(param2)..getStrParam(param3)..getStrParam(param4)..getStrParam(param5));
    print("print_OnCharacterDeath character:getUseHandWeapon ".. tostring(character)..getStrParam(character and character:getUseHandWeapon()));
    if not character or instanceof(character, "IsoPlayer") then return end
    print("print_OnCharacterDeath HitReaction".. getStrParam(character)..getStrParam(character:getHitReaction())..getStrParam(character:getActionStateName())..getStrParam(character:getTarget())..getStrParam(character:getAttackedBy()));
    if character:getTarget() and instanceof(character:getTarget(), "IsoGameCharacter") and character:getTarget():getVehicle() then 
        print("print_OnCharacterDeath Vehicle".. getStrParam(character)..getStrParam(character:getTarget():getVehicle())..getStrParam(character:getTarget():getVehicle():getDriver()));
    end
end

local function print_OnZombieDead(character, param2, param3, param4, param5)
    print("print_OnZombieDead ".. tostring(character)..getStrParam(param2)..getStrParam(param3)..getStrParam(param4)..getStrParam(param5));
    print("print_OnZombieDead character:getUseHandWeapon ".. tostring(character)..getStrParam(character and character:getUseHandWeapon()));
    print("print_OnZombieDead HitReaction ".. tostring(character)..getStrParam(character:getHitReaction())..getStrParam(character:getActionStateName())..getStrParam(character:getTarget())..getStrParam(character:getAttackedBy()));
    if character:getTarget() and instanceof(character:getTarget(), "IsoGameCharacter") and character:getTarget():getVehicle() then 
        print("print_OnZombieDead Vehicle ".. tostring(character)..getStrParam(character:getTarget():getVehicle())..getStrParam(character:getTarget():getVehicle():getDriver()));
    end
end

local function print_OnWeaponHitXp(character, weapon, character2, damage, param5)--this occurs for all weapon kills (at least in B41.61+) so we can substract them from car kills or fire kills if needed
    print("print_OnWeaponHitXp"..getStrParam(character)..getStrParam(weapon)..getStrParam(character2)..getStrParam(damage)..getStrParam(param5)..getStrParam(character:getHealth()));
end

local function print_OnWeaponHitCharacter(wielder, target, weapon, damageSplit, bIgnoreDamage, modDelta, bRemote)--TODO analyse for B42.15+
    print("print_OnWeaponHit"..getStrParam(target)..getStrParam(weapon)..getStrParam(wielder)..getStrParam(target:getHealth())..getStrParam(damageSplit)..getStrParam(bIgnoreDamage)..getStrParam(modDelta)..getStrParam(bRemote)..getStrParam(bodypart));
end--cut the name to get column alignement with print_OnHitZombie

local function print_OnHitZombie(target, wielder, bodypart, weapon, damageSplit)--TODO analyse for B42.15+
    print("print_OnHitZombie"..getStrParam(target)..getStrParam(weapon)..getStrParam(wielder)..getStrParam(target:getHealth())..getStrParam(damageSplit)..getStrParam(bIgnoreDamage)..getStrParam(modDelta)..getStrParam(bRemote)..getStrParam(bodypart));
end

if KillCount.Verbose then
    Events.OnCharacterDeath.Add(print_OnCharacterDeath);
    Events.OnZombieDead.Add(print_OnZombieDead);
    Events.OnWeaponHitXp.Add(print_OnWeaponHitXp);
    Events.OnHitZombie.Add(print_OnHitZombie);
    Events.OnWeaponHitCharacter.Add(print_OnWeaponHitCharacter);
end

--note B41.78.16 Exhausted spear critical kill:
--LOG  : General     , 1683824842605> print_OnWeaponHitXp zombie.characters.IsoZombie@2ba04e79 
--LOG  : General     , 1683824844670> print_OnZombieDead zombie.characters.IsoZombie@2ba04e79
--LOG  : General     , 1683824844672> print_OnCharacterDeath zombie.characters.IsoZombie@2ba04e79


--note B41.78.16 spear kill (assumed all weapon kill):
--+ crowbar foot huntingknife M16(FromCar)
--LOG  : General     , 1683826434255> print_OnZombieDead zombie.characters.IsoZombie@2ba04e79 nil nil nil nil
--LOG  : General     , 1683826434256> print_OnCharacterDeath zombie.characters.IsoZombie@2ba04e79 nil nil nil nil
--LOG  : General     , 1683826434258> print_OnWeaponHitXp zombie.characters.IsoPlayer@2dcf244b zombie.inventory.types.HandWeapon@6693becf zombie.characters.IsoZombie@2ba04e79 2.0940001010894775 nil 0

--note B41.78.16 car kill slow & medium & fast speed:
--LOG  : General     , 1683827117211> print_OnZombieDead Vehicle zombie.characters.IsoZombie@17698ed0 zombie.vehicles.BaseVehicle@7005188a zombie.characters.IsoPlayer@2dcf244b
--LOG  : General     , 1683827117213> print_OnCharacterDeath Vehicle zombie.characters.IsoZombie@17698ed0 zombie.vehicles.BaseVehicle@7005188a zombie.characters.IsoPlayer@2dcf244b

--note B41.52 Fire Kill:
--LOG  : General     , 1627414823547> print_OnZombieDeadzombie.characters.IsoZombie@2b9acecd
--LOG  : General     , 1627414824927> print_OnZombieDeadzombie.characters.IsoZombie@2b9acecd
--LOG  : General     , 1627414824927> print_OnCharacterDeathzombie.characters.IsoZombie@2b9acecd

--note B41.50 Car Kill:
--LOG  : General     , 1627143315165> print_OnCharacterDeath zombie.characters.IsoZombie@69a62a4b


--note B42.15.3 Animal Range Kill (solo). Animal death occures (visibly) long after last shot (OnCharacterDeath long after OnWeaponHitXp). parked fawn. It looks as if the beast is bleeding but OnWeaponHitXp occuring at bullet impact time seems to tell it is intended to die earlier.
--DEBUG: Combat       f:19646, t:1774282505198> CombatManager.pressedAttack         > Attacked zombie: dist: 4.1809053, chance: (62), crit: false (12.0%) from behind: true
--DEBUG: Combat       f:19647, t:1774282505215> SwipeStatePlayer.OnAnimEvent_AttackCollisionCheck> AttackType: 
--DEBUG: Combat       f:19647, t:1774282505215> CombatManager.calculateHitLocationDamage> Zombie got hit in Groin with a Base.Revolver_Long for 1.1611079 out of 1.1611079 after totalDef of 0.0% was applied
--LOG  : Lua          f:19647, t:1774282505216> print_OnWeaponHit IsoAnimal{  Name:null,  ID:323 } Base.Revolver_Long:zombie.inventory.types.HandWeapon@37774301 IsoPlayer{  Name:null,  ID:209 } 1.1611078977584839 1 nil nil nil nil
--DEBUG: Combat       f:19922, t:1774282509798> CombatManager.pressedAttack         > Attacked zombie: dist: 4.242897, chance: (62), crit: false (12.0%) from behind: true
--DEBUG: Combat       f:19923, t:1774282509814> SwipeStatePlayer.OnAnimEvent_AttackCollisionCheck> AttackType: 
--DEBUG: Combat       f:19923, t:1774282509815> CombatManager.calculateHitLocationDamage> Zombie got hit in Left Upper Arm with a Base.Revolver_Long for 0.0771858 out of 0.0771858 after totalDef of 0.0% was applied
--LOG  : Lua          f:19923, t:1774282509815> print_OnWeaponHit IsoAnimal{  Name:null,  ID:323 } Base.Revolver_Long:zombie.inventory.types.HandWeapon@37774301 IsoPlayer{  Name:null,  ID:209 } 0.07718580216169357 0.5660977959632874 nil nil nil nil
--LOG  : Lua          f:19923, t:1774282509816> print_OnWeaponHitXp IsoPlayer{  Name:null,  ID:209 } Base.Revolver_Long:zombie.inventory.types.HandWeapon@37774301 IsoAnimal{  Name:null,  ID:323 } 0.07718580216169357 1 1
--LOG  : Lua          f:20342, t:1774282516797> KillCount.clearTableOldMemories removed key IsoAnimal{  Name:null,  ID:323 }
--LOG  : Lua          f:20342, t:1774282516798> print_OnCharacterDeath IsoAnimal{  Name:null,  ID:323 } nil nil nil nil
--LOG  : Lua          f:20342, t:1774282516799> print_OnCharacterDeath character:getUseHandWeapon IsoAnimal{  Name:null,  ID:323 } nil
--DEBUG: Animal       f:20342, t:1774282516800> IsoAnimal.delete                    > Animal delete id=1
--DEBUG: Death        f:20342, t:1774282516801> IsoDeadBody.<init>                  > Corpse created { "IsoDeadBody" : { "ObjectID" : { "ObjectIDShort": {  }  , "ObjectID": { "id" : 15, "type" : "ObjectID type=DeadBody last=15 new=15" }  }, "characterOnlineID" : 1, "bFakeDead" : false, "bCrawling" : false, "fallOnFront" : false, "x" : 10899.726, "y" : 9986.476, "z" : 0.0, "m_angle" : -1.5613537, "m_persistentOutfitID" : 0 } }

--note B42.15.3 Zombie Range Kill (solo). No Xp case.
--DEBUG: Combat       f:1674, t:1774283454486> CombatManager.pressedAttack         > Attacked zombie: dist: 11.44495, chance: (16), crit: false (15.0%) from behind: true
--DEBUG: Combat       f:1675, t:1774283454498> SwipeStatePlayer.OnAnimEvent_AttackCollisionCheck> AttackType: 
--DEBUG: Combat       f:1675, t:1774283454499> CombatManager.processHit            > CombatManager::ProcessHit 335 isCameraTarget and hit BodyPart 2 - BODYPART_HEAD
--DEBUG: Combat       f:1675, t:1774283454499> CombatManager.processTargetedHit    > hitReaction = SHOT_HEAD_FWD
--DEBUG: Combat       f:1675, t:1774283454500> CombatManager.calculateHitLocationDamage> Zombie got hit in Neck with a Base.Revolver_Long for 4.6949263 out of 4.6949263 after totalDef of 0.0% was applied
--LOG  : Lua          f:1675, t:1774283454500> print_OnHitZombie IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}} Base.Revolver_Long:zombie.inventory.types.HandWeapon@56168e38 IsoPlayer{  Name:null,  ID:355 } 1 nil nil nil nil Torso_Lower
--LOG  : Lua          f:1675, t:1774283454501> print_OnWeaponHit IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}} Base.Revolver_Long:zombie.inventory.types.HandWeapon@56168e38 IsoPlayer{  Name:null,  ID:355 } 1 4.6949262619018555 nil nil nil nil
--LOG  : Lua          f:1675, t:1774283454502> KillCount.updateB41_52_OnZombieDead increase weapon kill 2. no vehicle
--LOG  : Lua          f:1675, t:1774283454502> Debug Table 1: [IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}}] 1774283454501
--LOG  : Lua          f:1675, t:1774283454503> print_OnZombieDead IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}} nil nil nil nil
--LOG  : Lua          f:1675, t:1774283454503> print_OnZombieDead character:getUseHandWeapon IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}} nil
--LOG  : Lua          f:1675, t:1774283454504> print_OnZombieDead HitReaction IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}} ShotHeadFwd idle nil IsoPlayer{  Name:null,  ID:355 }
--LOG  : Lua          f:1675, t:1774283454504> KillCount.updateB41_52_OnCharacterDeath after weapon kill ignore it. IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}} no vehicle
--LOG  : Lua          f:1675, t:1774283454504> Debug Table (empty)
--LOG  : Lua          f:1675, t:1774283454505> print_OnCharacterDeath IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}} nil nil nil nil
--LOG  : Lua          f:1675, t:1774283454505> print_OnCharacterDeath character:getUseHandWeapon IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}} nil
--LOG  : Lua          f:1675, t:1774283454506> print_OnCharacterDeath HitReaction IsoZombie{  Name:null,  ID:335  StateFlags:zombie.popman.ZombieStateFlags{ { Initialized, CanWalk, CanCrawlUnderVehicle }}} ShotHeadFwd idle nil IsoPlayer{  Name:null,  ID:355 }
--DEBUG: Combat       f:1675, t:1774283454507> IsoZombie.hitConsequences           > Zombie #335 got hit for 3.169075
--DEBUG: Combat       f:1675, t:1774283454509> CombatManager.processHit            > CombatManager::ProcessHit 335 isCameraTarget and hit BodyPart 2 - BODYPART_HEAD
--DEBUG: Combat       f:1675, t:1774283454509> CombatManager.processTargetedHit    > hitReaction = SHOT_HEAD_FWD02
--DEBUG: Death        f:1803, t:1774283456631> IsoDeadBody.<init>                  > Corpse created { "IsoDeadBody" : { "ObjectID" : { "ObjectIDShort": {  }  , "ObjectID": { "id" : 16, "type" : "ObjectID type=DeadBody last=16 new=16" }  }, "characterOnlineID" : -1, "bFakeDead" : false, "bCrawling" : false, "fallOnFront" : true, "x" : 10893.754, "y" : 9979.994, "z" : 0.0, "m_angle" : -2.4371488, "m_persistentOutfitID" : -2142961420 } }
