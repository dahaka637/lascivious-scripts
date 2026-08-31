if not (isServer and isServer()) then
	return
end

local BloodlustOTraitObj = nil

local function safeCall(key, fn)
	local ok, err = pcall(fn)
	if not ok then
		print("[BloodlustO][Server] " .. tostring(key) .. " failed: " .. tostring(err))
	end
	return ok
end

local function getTraitObj()
	if BloodlustOTraitObj then
		return BloodlustOTraitObj
	end

	if CharacterTrait and CharacterTrait.get and ResourceLocation then
		local ok, trait = pcall(function()
			return CharacterTrait.get(ResourceLocation.of("bloodlusto:bloodlusto"))
		end)
		if ok and trait then
			BloodlustOTraitObj = trait
			return BloodlustOTraitObj
		end
	end

	return nil
end

local function hasBloodlustOverwhelming(player)
	if not player then
		return false
	end

	local trait = getTraitObj()
	if not trait then
		return false
	end

	local ok, result = pcall(function()
		return player:hasTrait(trait)
	end)

	return ok and result == true
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

local function sandbox()
	SandboxVars = SandboxVars or {}
	SandboxVars.BloodlustO = SandboxVars.BloodlustO or {}
	return SandboxVars.BloodlustO
end

local function removeStat(stats, stat, amount)
	stats:set(stat, math.max(0, stats:get(stat) - amount))
end

local function onZombieDead(zombie, attacker)
	local player = getZombieAttacker(zombie, attacker)
	if not hasBloodlustOverwhelming(player) then
		return
	end

	local stats = player:getStats()
	if not stats then
		return
	end

	local SB = sandbox()
	local bloodlustChange = SB.KillBloodlustReduction or 10
	local happinessChange = SB.BloodlustChangeHappiness or 2
	local destressChange = SB.BloodlustChangeDestress or 5

	safeCall("onZombieDead", function()
		removeStat(stats, CharacterStat.BOREDOM, 100)
		removeStat(stats, CharacterStat.UNHAPPINESS, bloodlustChange * happinessChange)
		removeStat(stats, CharacterStat.STRESS, bloodlustChange * destressChange * 0.01)
		removeStat(stats, CharacterStat.NICOTINE_WITHDRAWAL, bloodlustChange * destressChange * 0.01)
	end)
end

Events.OnZombieDead.Remove(onZombieDead)
Events.OnZombieDead.Add(onZombieDead)
