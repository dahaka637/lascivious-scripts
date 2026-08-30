local function setCombatSpeed(character, handWeapon)
    if handWeapon:isRanged() then return end

    local combatSpeed = character:getVariableFloat("CombatSpeed", 0.0)
    if combatSpeed <= 0.0 then return end

    local swingAnim = handWeapon:getSwingAnim()
    if swingAnim == "Heavy" then
        combatSpeed = math.min(combatSpeed * 1.5, 1.51) --tried randomizing with (1.4 + (ZombRand(26) / 100.0))) but apparently it makes it really fast
        
    elseif swingAnim == "Stab" then
        combatSpeed = math.min(combatSpeed * 1.22, 1.23) 

    else
        combatSpeed = math.min(combatSpeed * 1.1, 1.11) 
    end

    character:setVariable("CombatSpeed", combatSpeed)
end

Events.OnWeaponSwing.Add(setCombatSpeed)
