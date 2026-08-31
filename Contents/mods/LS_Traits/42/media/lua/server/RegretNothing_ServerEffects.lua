if not (isServer and isServer()) then
	return
end

local RN_TraitObj = nil

local function safeCall(key, fn)
	local ok, err = pcall(fn)
	if not ok then
		print("[RegretNothing][Server] " .. tostring(key) .. " failed: " .. tostring(err))
	end
	return ok
end

local function getTraitObj()
	if RN_TraitObj then
		return RN_TraitObj
	end

	if CharacterTrait and CharacterTrait.get and ResourceLocation then
		local ok, trait = pcall(function()
			return CharacterTrait.get(ResourceLocation.of("RegretNothing:RegretNothing"))
		end)
		if ok and trait then
			RN_TraitObj = trait
			return RN_TraitObj
		end
	end

	return nil
end

local function hasRegretNothing(player)
	if not player then
		return false
	end

	local modData = player:getModData()
	if modData.RN_HasRegretNothingTrait == true then
		return true
	end

	local trait = getTraitObj()
	if not trait then
		return false
	end

	local ok, result = pcall(function()
		return player:hasTrait(trait)
	end)

	if ok and result == true then
		modData.RN_HasRegretNothingTrait = true
		return true
	end

	return false
end

local function getZombieAttacker(zombie, attacker)
	if attacker and instanceof(attacker, "IsoPlayer") then
		return attacker
	end

	if not zombie then
		return nil
	end

	local ok, attackedBy = pcall(function()
		return zombie:getAttackedBy()
	end)

	if ok and attackedBy and instanceof(attackedBy, "IsoPlayer") then
		return attackedBy
	end

	return nil
end

local function reduceStat(stats, stat, amount)
	stats:set(stat, math.max(0, stats:get(stat) - amount))
end

local function increaseStat(stats, stat, amount, cap)
	stats:set(stat, math.min(cap, stats:get(stat) + amount))
end

local function onZombieDead(zombie, attacker)
	local player = getZombieAttacker(zombie, attacker)
	if not hasRegretNothing(player) then
		return
	end

	local modData = player:getModData()
	modData.RN_LastKillTime = getGameTime():getWorldAgeHours()

	local stats = player:getStats()
	if not stats then
		return
	end

	safeCall("onZombieDead", function()
		reduceStat(stats, CharacterStat.BOREDOM, 25)
		reduceStat(stats, CharacterStat.UNHAPPINESS, 25)
	end)
end

local function everyTenMinutes()
	local players = getOnlinePlayers()
	if not players then
		return
	end

	local currentTime = getGameTime():getWorldAgeHours()

	for i = 0, players:size() - 1 do
		local player = players:get(i)
		if hasRegretNothing(player) then
			local modData = player:getModData()
			if not modData.RN_LastKillTime then
				modData.RN_LastKillTime = currentTime
			elseif currentTime - modData.RN_LastKillTime > 2.0 then
				local stats = player:getStats()
				if stats then
					safeCall("everyTenMinutes", function()
						increaseStat(stats, CharacterStat.BOREDOM, 3, 100)
						increaseStat(stats, CharacterStat.UNHAPPINESS, 3, 100)
					end)
				end
			end
		end
	end
end

local function everyOneMinute()
	local players = getOnlinePlayers()
	if not players then
		return
	end

	for i = 0, players:size() - 1 do
		local player = players:get(i)
		if hasRegretNothing(player) then
			local stats = player:getStats()
			if stats then
				safeCall("everyOneMinute", function()
					stats:set(CharacterStat.FOOD_SICKNESS, 0)
					stats:set(CharacterStat.POISON, 0)
				end)
			end
		end
	end
end

local function onWeaponHitCharacter(attacker, target, weapon, damageSplit)
	if not hasRegretNothing(attacker) then
		return
	end

	if not target or damageSplit == nil then
		return
	end

	local modData = attacker:getModData()
	if not modData.RN_ConsumableBuffEnd or getGameTime():getWorldAgeHours() >= modData.RN_ConsumableBuffEnd then
		return
	end

	safeCall("onWeaponHitCharacter", function()
		if target:getHealth() > 0 then
			target:setHealth(target:getHealth() - (damageSplit * 0.1))
		end
	end)
end

Events.OnZombieDead.Remove(onZombieDead)
Events.OnZombieDead.Add(onZombieDead)
Events.EveryTenMinutes.Remove(everyTenMinutes)
Events.EveryTenMinutes.Add(everyTenMinutes)
Events.EveryOneMinute.Remove(everyOneMinute)
Events.EveryOneMinute.Add(everyOneMinute)
Events.OnWeaponHitCharacter.Remove(onWeaponHitCharacter)
Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
