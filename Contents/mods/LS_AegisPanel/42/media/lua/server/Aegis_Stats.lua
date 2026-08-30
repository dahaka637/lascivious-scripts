-- Player values window, server side. Vanilla ISPlayerStatsUI mutates the
-- ADMIN copy of a foreign player, and that copy is the snapshot from the
-- connect packet: writing it back rolls every skill the target learned
-- since. Everything here changes the SERVER object instead, which the engine
-- pushes to the owner once a second (NetworkPlayerManager.update calls
-- syncXp and syncStats), so traits, xp, levels and weight go live by
-- themselves and persist with the character. The two values that ride in no
-- periodic packet get pushed by hand: the perk boost lives in
-- SurvivorDesc.xpBoostMap and goes to the target, names and profession live
-- in the vanilla ChangePlayerStats packet a server cannot send and go to
-- everyone, because every client draws the name tag from its own copy.
if isClient() then return end

require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"

local MAX_NAME = 32
local WEIGHT_MIN = 35
local WEIGHT_MAX = 130
local XP_MAX = 1000000
local LEVEL_MAX = 10
local BOOST_MAX = 3

-- tonumber("nan") really yields NaN, and every comparison against it is
-- false, so a plain clamp lets it through and the value is stored poisoned
-- for good. NaN is the only value that differs from itself. Infinity gets
-- the same treatment, it survives clamping just as badly
local function finite(v)
    local n = tonumber(v)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end
-- burst budget per second and sender. Reads build a full block, writes share
-- one slot so a manipulated client cannot spend them command by command
local READ_PER_SEC = 2
local WRITE_PER_SEC = 8
-- AddXP scales strength xp by the protein state, one pass rarely lands
-- exactly on the wanted level
local LEVEL_ROUNDS = 8
-- Nutrition.applyTraitFromWeight leaves 75 < w < 85 without a weight trait
local WEIGHT_NEUTRAL = 80

-- ---------- plumbing ----------

-- reply to the caller: over the network in MP, in solo straight to the
-- OnServerCommand listeners of the same process
local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

local function toTarget(target, command, args)
    if isServer() then
        sendServerCommand(target, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

-- three argument form is the broadcast, it reaches every connection
local function toEveryone(command, args)
    if isServer() then
        sendServerCommand(AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

local budget = {}

local function overBudget(name, slot, perSecond)
    local now = AegisShared.realTime()
    local key = name .. "\n" .. slot
    local entry = budget[key]
    if not entry or entry.sec ~= now then
        entry = { sec = now, n = 0 }
        budget[key] = entry
    end
    entry.n = entry.n + 1
    return entry.n > perSecond
end

local function senderName(player)
    local name = player:getUsername()
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local function userOf(target)
    return senderName(target) or "?"
end

local function round(v, digits)
    v = tonumber(v) or 0
    local f = (digits == 2) and 100 or 10
    if v >= 0 then return math.floor(v * f + 0.5) / f end
    return -(math.floor(-v * f + 0.5) / f)
end

local function cleanName(v)
    if type(v) ~= "string" then return nil end
    local s = v:gsub("[%c|]", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if #s > MAX_NAME then s = s:sub(1, MAX_NAME) end
    s = s:gsub("%s+$", "")
    return s
end

local function findByUsername(name)
    local players = getOnlinePlayers()
    if not players then return nil end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p:getUsername() == name then return p end
    end
    return nil
end

-- online id first, username as fallback. Solo keeps no online map, there the
-- one local player is the only reachable target. Offline characters cannot be
-- served at all, ServerPlayerDB is not exposed to Lua
local function resolveTarget(args)
    local id = tonumber(args and args.id)
    if id and id >= 0 then
        local found = nil
        pcall(function() found = getPlayerByOnlineID(id) end)
        if found then return found end
    end
    local name = (type(args) == "table" and type(args.username) == "string") and args.username or ""
    if name ~= "" then
        local found = findByUsername(name)
        if found then return found end
    end
    if not isServer() then
        local p = getPlayer()
        if p and (name == "" or p:getUsername() == name) then return p end
    end
    return nil
end

-- ---------- engine catalogues ----------

-- every id the client sends is looked up in a list the engine really holds.
-- A made up id must never reach CharacterTraits:add or setCharacterProfession,
-- a nil in there breaks the next character save

local perkCache = nil

local function perks()
    if perkCache then return perkCache end
    local cache = { byId = {}, order = {} }
    if PerkFactory and PerkFactory.PerkList then
        for i = 0, PerkFactory.PerkList:size() - 1 do
            local perk = PerkFactory.PerkList:get(i)
            local parent = perk and perk:getParent()
            -- vanilla filter: sentinels and category headers carry parent
            -- None and are no skills. Compared by id, Kahlua object identity
            -- on java objects is not dependable
            if parent and parent:getId() ~= "None" then
                local id = perk:getId()
                if id and not cache.byId[id] then
                    cache.byId[id] = perk
                    cache.order[#cache.order + 1] = perk
                end
            end
        end
    end
    -- empty means the scripts are not parsed yet, do not pin that
    if #cache.order > 0 then perkCache = cache end
    return cache
end

local traitCache = nil

local function traitCatalogue()
    if traitCache then return traitCache end
    local map = {}
    local count = 0
    local defs = CharacterTraitDefinition and CharacterTraitDefinition.getTraits()
    if defs then
        for i = 0, defs:size() - 1 do
            local def = defs:get(i)
            local t = def and def:getType()
            if t then
                map[tostring(t)] = t
                count = count + 1
            end
        end
    end
    if count > 0 then traitCache = map end
    return map
end

local profCache = nil

local function professionCatalogue()
    if profCache then return profCache end
    local map = {}
    local count = 0
    local defs = CharacterProfessionDefinition and CharacterProfessionDefinition.getProfessions()
    if defs then
        for i = 0, defs:size() - 1 do
            local def = defs:get(i)
            local p = def and def:getType()
            if p then
                map[tostring(p)] = p
                count = count + 1
            end
        end
    end
    if count > 0 then profCache = map end
    return map
end

-- the five weight traits with their vanilla target weight and the band that
-- derives them, read off Nutrition.applyWeightFromTraits and
-- applyTraitFromWeight
local weightCache = nil

local function weightTraits()
    if weightCache then return weightCache end
    local list = {}
    local function put(trait, want, test)
        if trait == nil then return end
        local id = tostring(trait)
        if id ~= "" and id ~= "nil" then
            list[#list + 1] = { id = id, want = want, test = test }
        end
    end
    if CharacterTrait then
        put(CharacterTrait.EMACIATED, 50, function(w) return w <= 50 end)
        put(CharacterTrait.VERY_UNDERWEIGHT, 60, function(w) return w > 50 and w <= 65 end)
        put(CharacterTrait.UNDERWEIGHT, 70, function(w) return w > 65 and w <= 75 end)
        put(CharacterTrait.OVERWEIGHT, 95, function(w) return w >= 85 and w < 100 end)
        put(CharacterTrait.OBESE, 105, function(w) return w >= 100 end)
    end
    if #list > 0 then weightCache = list end
    return list
end

local function weightRule(id)
    for _, row in ipairs(weightTraits()) do
        if row.id == id then return row end
    end
    return nil
end

-- ---------- reading ----------

-- ids only over the wire, the client resolves label, description and texture.
-- The dedicated server has no useful getText
-- deduplicated on purpose: CharacterTraits.set appends without checking
-- whether the trait is already there, so the engine list really can hold the
-- same trait twice (vanilla admin panel and mods both write into it). Showing
-- it twice looked like a bug of ours, and the second copy is invisible to the
-- player anyway
local function traitList(target)
    local list, seen = {}, {}
    local known = target:getCharacterTraits():getKnownTraits()
    for i = 0, known:size() - 1 do
        local t = known:get(i)
        if t then
            local id = tostring(t)
            if not seen[id] then
                seen[id] = true
                list[#list + 1] = id
            end
        end
    end
    return list
end

local function hasTraitId(target, id)
    for _, held in ipairs(traitList(target)) do
        if held == id then return true end
    end
    return false
end

-- the object out of the target's own known list, so a trait whose definition
-- disappeared with a mod can still be removed
local function knownTrait(target, id)
    local found = nil
    local known = target:getCharacterTraits():getKnownTraits()
    for i = 0, known:size() - 1 do
        local t = known:get(i)
        if t and tostring(t) == id then
            found = t
            break
        end
    end
    return found
end

local function perkRows(target)
    local rows = {}
    local xp = target:getXp()
    for _, perk in ipairs(perks().order) do
        local level = target:getPerkLevel(perk)
        local total = xp:getXP(perk)
        local base = perk:getTotalXpForLevel(level)
        rows[#rows + 1] = {
            id = perk:getId(),
            parent = perk:getParent():getId(),
            level = level,
            -- xp gained inside the current level, that is what a bar shows
            xp = round(total - base, 2),
            -- getXpForLevel returns -1 above level 10
            need = round(perk:getXpForLevel(level + 1), 2),
            boost = xp:getPerkBoost(perk),
            -- 0 means no personal multiplier, not factor one
            mult = round(xp:getMultiplier(perk), 2),
        }
    end
    return rows
end

-- Needs the admin may dial freely (community request: the vanilla debug
-- menu can set them, the panel could only reset everything to zero).
-- Curated and ordered, the engine knows 24 stats and most of the rest is
-- internal bookkeeping. The bounds are NOT hard coded: CharacterStat
-- carries getMinimumValue and getMaximumValue and the slider spans
-- exactly that, so a range change in a patch cannot desync us
local NEED_ORDER = {
    "HUNGER", "THIRST", "FATIGUE", "ENDURANCE", "STRESS", "PANIC",
    "BOREDOM", "UNHAPPINESS", "PAIN", "SICKNESS", "INTOXICATION", "WETNESS",
}

local NEED_ALLOWED = {}
for _, id in ipairs(NEED_ORDER) do NEED_ALLOWED[id] = true end

local function needRows(target)
    local rows = {}
    local stats = target:getStats()
    for _, id in ipairs(NEED_ORDER) do
        local stat = CharacterStat[id]
        if stat then
            local v = stats:get(stat)
            local lo = stat:getMinimumValue()
            local hi = stat:getMaximumValue()
            if type(v) == "number" then
                rows[#rows + 1] = { s = id, v = round(v, 3),
                    lo = tonumber(lo) or 0, hi = tonumber(hi) or 1 }
            end
        end
    end
    return rows
end

local function statsBlock(target)
    local block = {
        id = -1, username = "", forename = "", surname = "", displayName = "",
        profession = "", weight = 0, hours = 0, level = "", role = "",
    }
    block.id = target:getOnlineID()
    block.username = target:getUsername() or ""
    local d = target:getDescriptor()
    block.forename = d:getForename() or ""
    block.surname = d:getSurname() or ""
    local prof = d:getCharacterProfession()
    block.profession = prof and tostring(prof) or ""
    block.displayName = target:getDisplayName() or ""
    block.weight = round(target:getNutrition():getWeight(), 1)
    block.hours = round(target:getHoursSurvived(), 1)
    block.level = tostring(target:getAccessLevel() or ""):lower()
    block.asleep = target:isAsleep() == true
    if isServer() and AegisRoles and AegisRoles.assignedRole then
        block.role = AegisRoles.assignedRole(block.username) or ""
    end
    block.traits = traitList(target)
    block.perks = perkRows(target)
    block.needs = needRows(target)
    return block
end

-- every command answers with the same fresh block, never with the value the
-- admin hoped for: the admin copy of a foreign player is never refreshed by
-- the engine, so the window has no other source of truth
local function reply(player, action, target, extra)
    local block = statsBlock(target)
    block.action = action
    block.ok = true
    if type(extra) == "table" then
        for k, v in pairs(extra) do block[k] = v end
    end
    toClient(player, "statsData", block)
end

local function replyGone(player, action, args)
    toClient(player, "statsData", {
        action = action, ok = false, gone = true, reason = "offline",
        id = tonumber(args and args.id) or -1,
        username = (type(args) == "table" and type(args.username) == "string") and args.username or "",
        traits = {}, perks = {},
    })
end

local function fail(player, action, target, reason)
    reply(player, action, target, { ok = false, reason = reason })
end

-- ---------- pushes the engine does not do ----------

-- xpBoostMap sits in SurvivorDesc and travels in no packet, so both sides
-- drift apart the moment it moves. Absolute values for every perk, never a
-- delta: the same push applied twice must not double a boost
local function pushBoosts(target)
    local rows = {}
    local xp = target:getXp()
    for _, perk in ipairs(perks().order) do
        rows[#rows + 1] = { p = perk:getId(), v = xp:getPerkBoost(perk) }
    end
    if #rows == 0 then return end
    -- carry the identity: the targeted send only addresses the connection,
    -- and in splitscreen that connection holds several players
    local id = target:getOnlineID()
    local user = target:getUsername() or ""
    toTarget(target, "statsBoostApply", { boosts = rows, id = id, username = user })
end

-- names and profession ride only in ChangePlayerStats, which is client only
-- and capability gated, so the server cannot trigger it. Broadcast instead,
-- getPlayerByOnlineID resolves every connected player on every client
local function pushIdentity(target, auto)
    local payload = {
        auto = auto == true, id = -1, username = "",
        forename = "", surname = "", displayName = "", profession = "",
    }
    payload.id = target:getOnlineID()
    payload.username = target:getUsername() or ""
    local d = target:getDescriptor()
    payload.forename = d:getForename() or ""
    payload.surname = d:getSurname() or ""
    local prof = d:getCharacterProfession()
    payload.profession = prof and tostring(prof) or ""
    payload.displayName = target:getDisplayName() or ""
    toEveryone("statsIdentityApply", payload)
end

-- ---------- xp helpers ----------

local function xpOf(target, perk)
    return target:getXp():getXP(perk)
end

-- always through the globals, never getXp():AddXP() directly: only
-- GameServer.addXp calls updateXpChecker afterwards, and without that the
-- anti cheat flags the TARGET for the xp jump the admin caused
local function grant(target, perk, amount, useMultipliers)
    return pcall(function()
        if useMultipliers then
            addXp(target, perk, amount)
        else
            addXpNoMultiplier(target, perk, amount)
        end
    end)
end

-- vanilla arithmetic, but against the server value instead of the stale admin
-- copy, and repeated: strength xp is scaled by the protein state, so a single
-- pass overshoots or falls short
local function reachLevel(target, perk, want)
    local goal = perk:getTotalXpForLevel(want)
    for _ = 1, LEVEL_ROUNDS do
        local have = xpOf(target, perk)
        local delta = goal - have
        if math.abs(delta) < 0.5 then return true end
        if not grant(target, perk, delta, false) then return false end
        if xpOf(target, perk) == have then return false end
    end
    return math.abs(goal - xpOf(target, perk)) < 0.5
end

-- exact but without the level sound and without the LevelPerk event, so only
-- used when the arithmetic route did not converge
local function forceLevel(target, perk, want)
    return pcall(function()
        target:getXp():setXPToLevel(perk, want)
        -- setXPToLevel only moves xpMap, the level itself sits in perkList
        target:setPerkLevelDebug(perk, want)
        if perk:getId() == "Fitness" then
            target:getStats():set(CharacterStat.FITNESS, want / 5 - 1)
        end
        -- no xp, pure trigger so updateXpChecker picks up the new baseline
        addXpNoMultiplier(target, perk, 0)
    end)
end

-- ---------- commands ----------

local Commands = {}

local NAME_KINDS = { fore = true, sur = true, disp = true }
local XP_MODES = { xp = true, up = true, down = true, level = true, boost = true }

Commands.statsRead = function(player, args)
    local target = resolveTarget(args)
    if not target then
        replyGone(player, "read", args)
        return
    end
    reply(player, "read", target)
end

-- traits: server only. CharacterTraits is the first block in XP.save, so the
-- one second syncXp push carries the change to the owner on its own, and
-- IsoGameCharacter.save persists it. Only the boost map needs the extra push
Commands.statsTrait = function(player, args, admin)
    local target = resolveTarget(args)
    if not target then
        replyGone(player, "trait", args)
        return
    end
    local id = type(args.trait) == "string" and args.trait or ""
    local add = args.add == true
    local held = hasTraitId(target, id)
    if id == "" then
        fail(player, "trait", target, "value")
        return
    end
    if add == held then
        fail(player, "trait", target, "same")
        return
    end
    -- for a removal take the instance out of the target's own list, that one
    -- is guaranteed to match List.remove and still works for a trait whose
    -- definition left with a mod; an addition can only come from the catalogue
    local trait
    if add then
        trait = traitCatalogue()[id]
    else
        trait = knownTrait(target, id) or traitCatalogue()[id]
    end
    if not trait then
        fail(player, "trait", target, "value")
        return
    end
    local done
    if add then
        -- CharacterTraits.set appends without a contains test, a second add
        -- would leave a duplicate that survives save and network
        done = pcall(function()
            target:getCharacterTraits():add(trait)
            target:modifyTraitXPBoost(trait, false)
        end)
    else
        done = pcall(function()
            local ct = target:getCharacterTraits()
            ct:remove(trait)
            -- remove drops one entry only, an old duplicate would stay
            for _ = 1, 3 do
                if not hasTraitId(target, id) then break end
                ct:remove(trait)
            end
            -- exactly once, modifyTraitXPBoost does not clamp and would run
            -- the boost map negative
            target:modifyTraitXPBoost(trait, true)
        end)
        if done and hasTraitId(target, id) then done = false end
    end
    if not done then
        fail(player, "trait", target, "engine")
        return
    end
    local text = (add and "Trait added: " or "Trait removed: ") .. id
    local extra = nil
    -- the server rederives the five weight traits from the weight every 2000
    -- nutrition ticks, so a hand set one silently reverts. Move the weight
    -- into the matching band and say so
    local rule = weightRule(id)
    if rule then
        local now = target:getNutrition():getWeight()
        if type(now) == "number" then
            local set = nil
            if add and math.abs(now - rule.want) > 0.5 then
                set = rule.want
            elseif not add and rule.test(now) then
                set = WEIGHT_NEUTRAL
            end
            if set and pcall(function() target:getNutrition():setWeight(set) end) then
                extra = { note = "weight", noteValue = set }
                text = text .. " (weight set to " .. tostring(set) .. ")"
            end
        end
    end
    AegisLog.write("Actions", admin, userOf(target), text)
    pushBoosts(target)
    reply(player, "trait", target, extra)
end

-- profession: broadcast, it sits in SurvivorDesc and no periodic packet
-- carries it. Label only, like vanilla: setProfessionSkills ADDS to the boost
-- map instead of replacing it and would stack the old job onto the new one
Commands.statsProfession = function(player, args, admin)
    local target = resolveTarget(args)
    if not target then
        replyGone(player, "profession", args)
        return
    end
    local id = type(args.profession) == "string" and args.profession or ""
    local prof = professionCatalogue()[id]
    if not prof then
        fail(player, "profession", target, "value")
        return
    end
    local p = target:getDescriptor():getCharacterProfession()
    local before = p and tostring(p) or ""
    if before == id then
        fail(player, "profession", target, "same")
        return
    end
    if not pcall(function() target:getDescriptor():setCharacterProfession(prof) end) then
        fail(player, "profession", target, "engine")
        return
    end
    AegisLog.write("Actions", admin, userOf(target),
        "Profession set to " .. id .. " (was " .. (before ~= "" and before or "none") .. ")")
    pushIdentity(target)
    reply(player, "profession", target)
end

-- names: broadcast for the same reason as the profession, plus every client
-- draws the tag over the head from its own copy
Commands.statsName = function(player, args, admin)
    local target = resolveTarget(args)
    if not target then
        replyGone(player, "name", args)
        return
    end
    local kind = type(args.kind) == "string" and args.kind or ""
    if not NAME_KINDS[kind] then
        fail(player, "name", target, "value")
        return
    end
    local value = cleanName(args.value)
    if value == nil then
        fail(player, "name", target, "value")
        return
    end
    -- an empty display name means back to automatic, an empty fore or
    -- surname would leave the character nameless
    local auto = kind == "disp" and value == ""
    if value == "" and not auto then
        fail(player, "name", target, "value")
        return
    end
    local before = ""
    if kind == "fore" then
        before = target:getDescriptor():getForename() or ""
    elseif kind == "sur" then
        before = target:getDescriptor():getSurname() or ""
    else
        before = target:getDisplayName() or ""
    end
    if not auto and before == value then
        fail(player, "name", target, "same")
        return
    end
    local done = pcall(function()
        if kind == "fore" then
            target:getDescriptor():setForename(value)
        elseif kind == "sur" then
            target:getDescriptor():setSurname(value)
        elseif auto then
            -- clears the field, the next read derives it again from the
            -- names or the username
            target:resetDisplayName()
        else
            target:setDisplayName(value)
        end
    end)
    if not done then
        fail(player, "name", target, "engine")
        return
    end
    local label = "Forename"
    if kind == "sur" then label = "Surname" end
    if kind == "disp" then label = "Display name" end
    AegisLog.write("Actions", admin, userOf(target),
        auto and (label .. " reset to automatic") or (label .. " set to " .. value))
    pushIdentity(target, auto)
    reply(player, "name", target)
end

-- weight: server only. Nutrition rides in the one second PlayerStats push,
-- and the whole calorie math runs server side anyway, so a client side set
-- would be overwritten right back
Commands.statsWeight = function(player, args, admin)
    local target = resolveTarget(args)
    if not target then
        replyGone(player, "weight", args)
        return
    end
    local w = finite(args.weight)
    if not w then
        fail(player, "weight", target, "value")
        return
    end
    -- setWeight clamps low at 35 and drains health below that, and does not
    -- clamp high at all
    if w < WEIGHT_MIN then w = WEIGHT_MIN end
    if w > WEIGHT_MAX then w = WEIGHT_MAX end
    w = round(w, 1)
    local before = target:getNutrition():getWeight()
    if type(before) == "number" and math.abs(before - w) < 0.05 then
        fail(player, "weight", target, "same")
        return
    end
    if not pcall(function() target:getNutrition():setWeight(w) end) then
        fail(player, "weight", target, "engine")
        return
    end
    AegisLog.write("Actions", admin, userOf(target), "Weight set to " .. tostring(w))
    reply(player, "weight", target)
end

-- one need to an exact value. Stats.set clamps by itself, but the value is
-- clamped here as well so the log line says what really landed. Server
-- only: the stats travel in the regular player packet, the target does not
-- have to do anything
Commands.statsNeed = function(player, args, admin)
    local target = resolveTarget(args)
    if not target then
        replyGone(player, "need", args)
        return
    end
    local id = type(args.stat) == "string" and args.stat or ""
    if not NEED_ALLOWED[id] then
        fail(player, "need", target, "value")
        return
    end
    local want = finite(args.value)
    if not want then
        fail(player, "need", target, "value")
        return
    end
    local stat = CharacterStat[id]
    if not stat then
        fail(player, "need", target, "value")
        return
    end
    local applied = nil
    local ok = pcall(function()
        want = stat:clamp(want)
        target:getStats():set(stat, want)
        applied = target:getStats():get(stat)
    end)
    if not ok then
        fail(player, "need", target, "engine")
        return
    end
    -- the drag sends four times a second, the release sends the final value
    -- again without the flag. Logging every step would fill the protocol
    -- with the way to the value instead of the value
    if args.quiet ~= true then
        AegisLog.write("Actions", admin, userOf(target),
            id .. " set to " .. tostring(round(applied or want, 3)))
    end
    -- the flag only travels back, it grants nothing. The client sets it
    -- while a slider is being dragged and skips toast and rebuild on the
    -- answer. A failure stays loud, the admin has to see that one
    reply(player, "need", target, args.quiet == true and { quiet = true } or nil)
end

-- xp, levels and boost. xp and levels are server only, XP.save carries xpMap
-- and perkList in the one second push. The boost is the exception, it lives
-- in SurvivorDesc and needs pushBoosts
Commands.statsXp = function(player, args, admin)
    local target = resolveTarget(args)
    if not target then
        replyGone(player, "xp", args)
        return
    end
    local mode = type(args.mode) == "string" and args.mode or ""
    if not XP_MODES[mode] then
        fail(player, "xp", target, "value")
        return
    end
    local perk = perks().byId[type(args.perk) == "string" and args.perk or ""]
    if not perk then
        fail(player, "xp", target, "value")
        return
    end
    local perkId = perk:getId()

    if mode == "boost" then
        local n = finite(args.boost)
        if not n then
            fail(player, "xp", target, "value")
            return
        end
        n = math.floor(n)
        if n < 0 or n > BOOST_MAX then
            fail(player, "xp", target, "value")
            return
        end
        local before = target:getXp():getPerkBoost(perk)
        if before == n then
            fail(player, "xp", target, "same")
            return
        end
        if not pcall(function() target:getXp():setPerkBoost(perk, n) end) then
            fail(player, "xp", target, "engine")
            return
        end
        AegisLog.write("Actions", admin, userOf(target),
            "XP boost " .. perkId .. ": " .. tostring(before) .. " -> " .. tostring(n))
        pushBoosts(target)
        reply(player, "xp", target)
        return
    end

    -- AddXP bails out on its first line when the target sleeps, and
    -- GameServer.addXp skips a dead one. Both calls would look successful and
    -- change nothing, so say it instead
    local blocked = nil
    if target:isAsleep() == true then blocked = "asleep" end
    if target:isDead() == true then blocked = "dead" end
    if blocked then
        fail(player, "xp", target, blocked)
        return
    end

    if mode == "xp" then
        local amount = finite(args.amount)
        if not amount or amount == 0 then
            fail(player, "xp", target, "value")
            return
        end
        if amount > XP_MAX then amount = XP_MAX end
        if amount < -XP_MAX then amount = -XP_MAX end
        local before = xpOf(target, perk)
        if not grant(target, perk, amount, args.mult == true) then
            fail(player, "xp", target, "engine")
            return
        end
        local after = xpOf(target, perk)
        AegisLog.write("Actions", admin, userOf(target),
            "XP " .. perkId .. " " .. tostring(round(amount, 2))
            .. (args.mult == true and " (multipliers)" or "")
            .. " -> " .. tostring(round(after, 2)))
        -- the engine clamps at 0 and at the level 10 total, so an unchanged
        -- value is a real outcome and not an error
        reply(player, "xp", target, (after == before) and { note = "noeffect" } or nil)
        return
    end

    local want
    if mode == "level" then
        want = finite(args.level)
        if not want then
            fail(player, "xp", target, "value")
            return
        end
    else
        local cur = target:getPerkLevel(perk)
        if cur < 0 then
            fail(player, "xp", target, "engine")
            return
        end
        want = cur + (mode == "up" and 1 or -1)
    end
    want = math.floor(want)
    if want < 0 then want = 0 end
    if want > LEVEL_MAX then want = LEVEL_MAX end
    local before = target:getPerkLevel(perk)
    if before == want then
        fail(player, "xp", target, "same")
        return
    end
    local note = nil
    if not reachLevel(target, perk, want) then
        if not forceLevel(target, perk, want) then
            fail(player, "xp", target, "engine")
            return
        end
        -- no LevelPerk event and no level sound on this route, listeners of
        -- other mods do not see the change
        note = "forced"
    end
    local after = target:getPerkLevel(perk)
    AegisLog.write("Actions", admin, userOf(target),
        "Skill " .. perkId .. " level " .. tostring(before) .. " -> " .. tostring(after))
    reply(player, "xp", target, note and { note = note } or nil)
end

-- ---------- dispatch ----------

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- a suspended sender keeps no authority in any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if not Commands[command] then return end
    local name = senderName(player)
    if not name then return end
    -- budget FIRST, like followPos: a client that lost the right keeps
    -- sending, and the deny answer must not flood either
    local read = command == "statsRead"
    if overBudget(name, read and "statsRead" or "statsWrite",
        read and READ_PER_SEC or WRITE_PER_SEC) then
        return
    end
    if not AegisRoles.canArea(player, "players") then
        toClient(player, "denied", { area = "players" })
        return
    end
    Commands[command](player, type(args) == "table" and args or {}, name)
end

Events.OnClientCommand.Add(onClientCommand)
