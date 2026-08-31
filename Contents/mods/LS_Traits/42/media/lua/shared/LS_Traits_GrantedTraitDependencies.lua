-- Lascivious Traits - runtime/migration guard for granted trait dependencies.
--
-- Character creation handles GrantedTraits for new characters, but existing
-- saves and dynamically-earned traits need a one-shot safety pass.

local Granted = {}

local function trait(resource)
	if not (CharacterTrait and CharacterTrait.get and ResourceLocation) then return nil end
	local ok, value = pcall(function()
		return CharacterTrait.get(ResourceLocation.of(resource))
	end)
	return ok and value or nil
end

local function hasTrait(player, tr)
	if not (player and tr) then return false end
	local ok, value = pcall(function() return player:hasTrait(tr) end)
	return ok and value == true
end

local function addTrait(player, tr)
	if not (player and tr and player.getCharacterTraits) then return false end
	local ok = pcall(function() player:getCharacterTraits():add(tr) end)
	return ok == true
end

local function username(player)
	local ok, value = pcall(function() return player:getUsername() end)
	return ok and tostring(value) or "?"
end

local dependencies = nil
local function getDependencies()
	if dependencies then return dependencies end
	dependencies = {
		{
			source = trait("RegretNothing:RegretNothing"),
			granted = trait("base:desensitized") or (CharacterTrait and CharacterTrait.DESENSITIZED or nil),
			label = "RegretNothing->Desensitized",
		},
		{
			source = trait("bloodlusto:bloodlusto"),
			granted = trait("base:desensitized") or (CharacterTrait and CharacterTrait.DESENSITIZED or nil),
			label = "BloodlustOverwhelming->Desensitized",
		},
	}
	return dependencies
end

function Granted.ensure(player, reason)
	if not player then return 0 end
	local applied = 0
	for _, dep in ipairs(getDependencies()) do
		if dep.source and dep.granted and hasTrait(player, dep.source) and not hasTrait(player, dep.granted) then
			if addTrait(player, dep.granted) then
				applied = applied + 1
				print("[LS_Traits/Granted] added granted trait dependency " .. dep.label
					.. " for " .. username(player) .. " (" .. tostring(reason or "ensure") .. ")")
			end
		end
	end
	return applied
end

local seen = setmetatable({}, { __mode = "k" })
local function ensureOnce(player, reason)
	if not player or seen[player] then return end
	seen[player] = true
	Granted.ensure(player, reason)
end

local function onCreatePlayer(a, b)
	local player = b or a
	ensureOnce(player, "OnCreatePlayer")
end

local function onGameStart()
	if getPlayer then ensureOnce(getPlayer(), "OnGameStart") end
end

if Events then
	if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end
	if Events.OnGameStart then Events.OnGameStart.Add(onGameStart) end
end

return Granted
