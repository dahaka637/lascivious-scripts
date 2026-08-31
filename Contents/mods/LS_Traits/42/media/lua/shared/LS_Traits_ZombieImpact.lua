-- Lascivious Traits - common zombie impact helpers.
--
-- B42 exposes IsoZombie:knockDown(boolean), which is a better "make this
-- zombie enter the knockdown state" transition than only flipping the inherited
-- IsoGameCharacter:setKnockedDown(true) boolean.  Keep the setter as fallback
-- for compatibility, but prefer the zombie-specific transition everywhere.

local ZombieImpact = {}

local function safe(fn, fallback)
	local ok, value = pcall(fn)
	if ok then return value end
	return fallback
end

function ZombieImpact.onlineID(zombie)
	if not zombie then return nil end
	return safe(function() return zombie:getOnlineID() end, nil)
end

function ZombieImpact.isRemoteZombie(zombie)
	if not (isClient() and zombie) then return false end
	return safe(function() return zombie:isRemoteZombie() end, false) == true
end

function ZombieImpact.ownerPlayer(zombie)
	if not zombie then return nil end
	local owner = safe(function() return zombie:getOwnerPlayer() end, nil)
	if owner and instanceof(owner, "IsoPlayer") then return owner end
	return nil
end

function ZombieImpact.findZombieByOnlineID(onlineID)
	onlineID = tonumber(onlineID)
	if not onlineID or not getCell then return nil end
	local zombies = getCell():getZombieList()
	if not zombies then return nil end
	for i = 0, zombies:size() - 1 do
		local zombie = zombies:get(i)
		if zombie and ZombieImpact.onlineID(zombie) == onlineID then
			return zombie
		end
	end
	return nil
end

function ZombieImpact.apply(zombie, opts)
	opts = opts or {}
	local result = {
		onlineID = ZombieImpact.onlineID(zombie),
		staggerCalled = false,
		knockDownCalled = false,
		knockDownFallback = false,
		confirmed = false,
		skippedRemote = false,
	}

	if not zombie then return result end
	if safe(function() return zombie:isDead() end, false) then return result end

	if ZombieImpact.isRemoteZombie(zombie) and opts.allowRemoteClient ~= true then
		result.skippedRemote = true
		return result
	end

	if opts.stagger ~= false then
		result.staggerCalled = safe(function()
			zombie:setStaggerBack(true)
			return true
		end, false) == true
	end

	if opts.knockDown == true then
		result.knockDownCalled = safe(function()
			zombie:knockDown(false)
			return true
		end, false) == true

		if not result.knockDownCalled then
			result.knockDownFallback = safe(function()
				zombie:setKnockedDown(true)
				return true
			end, false) == true
		end
	end

	if opts.update ~= false then
		safe(function() zombie:update() end, nil)
	end

	result.confirmed = safe(function() return zombie:isKnockedDown() end, false) == true
	return result
end

function ZombieImpact.applyRadialBurst(player, opts)
	opts = opts or {}
	local result = {
		targets = 0,
		knockDownCalls = 0,
		confirmed = 0,
		skippedRemote = 0,
	}
	if not player or not getCell then return result end

	local radius = math.max(0, tonumber(opts.radius) or 0)
	if radius <= 0 then return result end
	local radiusSq = radius * radius
	local limit = math.max(0, math.floor(tonumber(opts.limit) or 9999))
	local chance = math.max(0, math.min(100, tonumber(opts.knockDownChance) or 100))
	local except = opts.except
	local candidates = {}

	local px, py, pz = player:getX(), player:getY(), player:getZ()
	local zombies = getCell():getZombieList()
	if not zombies then return result end

	for i = 0, zombies:size() - 1 do
		local zombie = zombies:get(i)
		if zombie and zombie ~= except and not safe(function() return zombie:isDead() end, false) then
			local dz = safe(function() return zombie:getZ() end, pz) - pz
			if math.abs(dz) <= 0.1 then
				local dx = zombie:getX() - px
				local dy = zombie:getY() - py
				local d2 = dx * dx + dy * dy
				if d2 <= radiusSq then
					candidates[#candidates + 1] = { zombie = zombie, d2 = d2 }
				end
			end
		end
	end

	table.sort(candidates, function(a, b) return a.d2 < b.d2 end)
	for _, item in ipairs(candidates) do
		if result.targets >= limit then break end
		local doKnockDown = opts.knockDown == true
		if doKnockDown and chance < 100 then
			doKnockDown = ZombRandFloat and ZombRandFloat(0, 100) <= chance or ZombRand(100) < chance
		end
		local applied = ZombieImpact.apply(item.zombie, {
			stagger = opts.stagger ~= false,
			knockDown = doKnockDown,
			update = opts.update,
			allowRemoteClient = opts.allowRemoteClient,
		})
		result.targets = result.targets + 1
		if applied.skippedRemote then result.skippedRemote = result.skippedRemote + 1 end
		if applied.knockDownCalled or applied.knockDownFallback then result.knockDownCalls = result.knockDownCalls + 1 end
		if applied.confirmed then result.confirmed = result.confirmed + 1 end
	end

	return result
end

return ZombieImpact
