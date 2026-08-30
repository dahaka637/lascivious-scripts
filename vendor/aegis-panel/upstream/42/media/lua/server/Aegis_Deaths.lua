-- Death dossiers: the client report is the primary source (only the dying
-- client can read wounds and stats in full), a server side OnCharacterDeath
-- net catches clients that never sent one. One file per death under
-- Aegis/Log/Deaths/.
if isClient() then return end

require "Aegis_Store"
require "Aegis_Roles"
require "Aegis_Log"
require "Aegis_Moderation"

-- reply to the caller: over the network in MP, in solo directly to the
-- OnServerCommand listeners of the same process
local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, AegisShared.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", AegisShared.MODULE, command, args)
    end
end

local THROTTLE = 10
local NET_DELAY = 60
local NEAR_DIST = 60
local HOLD_MAX = 120
local DAY_CAP = 30

-- username -> epoch of the last accepted report, throttle and net dedupe
local lastReport = {}
-- safety net: username -> minimal facts captured at OnCharacterDeath
local pending = {}
-- reports from senders the server has not seen dead yet: username ->
-- {args, x, y, z, epoch}; written once the death is confirmed, dropped
-- after HOLD_MAX (a living client faking a report never gets a file)
local held = {}
-- username -> {day, n}: hard daily ceiling, Deaths is the one log area
-- an unprivileged client can fill and it never rotates
local dayCount = {}

local function cap(v, max)
    -- length alone is not enough: control characters would let a client
    -- smuggle forged lines into the dossier admins read as evidence
    local s = tostring(v):gsub("%c", " ")
    if #s > max then s = s:sub(1, max) end
    return s
end

-- online players around the death spot, admins marked; empty in solo
local function nearbyLines(x, y, victim)
    local lines = {}
    if not x or not y then return lines end
    local players = nil
    pcall(function() players = getOnlinePlayers() end)
    if not players then return lines end
    local n = 0
    pcall(function() n = players:size() end)
    for i = 0, n - 1 do
        pcall(function()
            local p = players:get(i)
            if p and p:getUsername() ~= victim then
                local dx, dy = p:getX() - x, p:getY() - y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= NEAR_DIST then
                    local line = p:getUsername() .. " (" .. math.floor(dist + 0.5) .. " tiles)"
                    if AegisRoles.isVanillaAdmin(p) then line = line .. " [admin]" end
                    if #lines < 40 then table.insert(lines, line) end
                end
            end
        end)
    end
    return lines
end

local function notifyAdmins(victim)
    -- solo: the only player is dead, nobody left to toast
    if not isServer() then return end
    pcall(function()
        local players = getOnlinePlayers()
        if not players then return end
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p and AegisRoles.isVanillaAdmin(p) then
                toClient(p, "deathNotice", { key = "UI_Aegis_DeathNotice", par = cap(victim, 48) })
            end
        end
    end)
end

local function attackerLine(a)
    if type(a) ~= "table" then return nil end
    local out = cap(a.kind or "unknown", 16)
    if a.name then out = out .. " " .. cap(a.name, 48) end
    if a.detail then out = out .. " (" .. cap(a.detail, 96) .. ")" end
    if a.weapon then out = out .. ", weapon: " .. cap(a.weapon, 48) end
    return out
end

local function buildDossier(name, args, x, y, z)
    local t = {}
    local function add(label, value)
        if value == nil or value == "" then return end
        table.insert(t, label .. ": " .. tostring(value))
    end
    add("Victim", cap(name, 48))
    if args.failed == true then add("Note", "client collection failed, partial data") end
    add("Game time", args.igTime and cap(args.igTime, 32) or nil)
    if x and y then
        add("Position", math.floor(x) .. "," .. math.floor(y) .. "," .. math.floor(z or 0))
    end
    add("Room", args.room and cap(args.room, 48) or nil)
    add("Zone", args.zone and cap(args.zone, 48) or nil)
    add("Vehicle", args.vehicle and cap(args.vehicle, 64) or nil)
    add("Attacker", attackerLine(args.attacker))
    if args.onFire == true then add("On fire", "yes") end
    if args.burnt == true then add("Burnt to death", "yes") end
    add("Knox infection", args.infected == true and "yes" or "no")
    add("Infection level", tonumber(args.infectionLevel))
    add("Infection hours", tonumber(args.infectionTime))
    add("Zombie fever", tonumber(args.fever))
    add("Poison", tonumber(args.poison))
    add("Food sickness", tonumber(args.foodSickness))
    add("Core temperature", tonumber(args.coreTemp))
    add("Hunger", tonumber(args.hunger))
    add("Thirst", tonumber(args.thirst))
    add("Hours survived", tonumber(args.hoursSurvived))
    add("Zombie kills", tonumber(args.zombieKills))
    add("Survivor kills", tonumber(args.survivorKills))
    add("Zombies within 15 tiles", tonumber(args.zombiesNear))
    if type(args.wounds) == "table" and #args.wounds > 0 then
        table.insert(t, "Wounds:")
        for i = 1, math.min(#args.wounds, 25) do
            table.insert(t, "  " .. cap(args.wounds[i], 120))
        end
    end
    if type(args.skills) == "table" and #args.skills > 0 then
        table.insert(t, "Skills lost (" .. #args.skills .. "):")
        for i = 1, math.min(#args.skills, 40) do
            table.insert(t, "  " .. cap(args.skills[i], 64))
        end
    else
        table.insert(t, "Skills lost: none above zero")
    end
    if type(args.recipes) == "table" and #args.recipes > 0 then
        local total = tonumber(args.recipeTotal) or #args.recipes
        local head = "Recipes lost (" .. total .. ")"
        if total > #args.recipes then head = head .. ", first " .. #args.recipes .. " listed" end
        table.insert(t, head .. ":")
        for i = 1, #args.recipes do
            table.insert(t, "  " .. cap(args.recipes[i], 64))
        end
    else
        table.insert(t, "Recipes lost: none")
    end
    local near = nearbyLines(x, y, name)
    if #near > 0 then
        table.insert(t, "Players nearby (" .. NEAR_DIST .. " tiles):")
        for _, line in ipairs(near) do table.insert(t, "  " .. line) end
    else
        table.insert(t, "Players nearby (" .. NEAR_DIST .. " tiles): none")
    end
    return table.concat(t, "\n")
end

local function underDayCap(name)
    local day = AegisShared.dateShort(AegisShared.realTime())
    local e = dayCount[name]
    if not e or e.day ~= day then
        e = { day = day, n = 0 }
        dayCount[name] = e
    end
    e.n = e.n + 1
    if e.n == DAY_CAP + 1 then
        print("[Aegis] death dossier day cap reached for " .. tostring(name))
    end
    return e.n <= DAY_CAP
end

local function writeReport(name, args, x, y, z, note)
    if not underDayCap(name) then return end
    pending[name] = nil
    local text = buildDossier(name, args, x, y, z)
    if note then text = text .. "\nNote: " .. note end
    AegisLog.write("Deaths", name, name, text)
    notifyAdmins(name)
end

local Commands = {}

-- the victim is always the sender himself, names inside args are never
-- trusted; args = {} arrives as nil
Commands.deathReport = function(player, args)
    args = args or {}
    local name = player:getUsername()
    if type(name) ~= "string" or name == "" then return end
    local now = AegisShared.realTime()
    if lastReport[name] and now - lastReport[name] < THROTTLE then return end
    lastReport[name] = now
    -- position: the server's own view wins, client numbers are the fallback
    local x, y, z = player:getX(), player:getY(), player:getZ()
    x = x or tonumber(args.x)
    y = y or tonumber(args.y)
    z = z or tonumber(args.z) or 0
    -- only a death the server can see becomes a file right away: the
    -- sender is dead, or OnCharacterDeath already parked this death.
    -- Anything else waits in held until the death confirms, otherwise
    -- a living client could mint evidence files at will
    local dead = player:isDead() == true
    if dead or pending[name] then
        writeReport(name, args, x, y, z)
    else
        held[name] = { args = args, x = x, y = y, z = z, epoch = now }
    end
end

-- ---------- safety net ----------
-- OnCharacterDeath fires server side for EVERY death, zombies and animals
-- included, so the cheap filter comes first. IsoAnimal extends IsoPlayer
-- in B42, the isAnimal check must run before the instanceof check.
-- The client report usually arrives seconds after this, so the minimal
-- facts are parked and only written once no report showed up in time.
local function onCharacterDeath(c)
    local isPlayer = c ~= nil and not c:isZombie() and not c:isAnimal()
        and instanceof(c, "IsoPlayer")
    if not isPlayer then return end
    local name = c:getUsername()
    if type(name) ~= "string" or name == "" then return end
    local now = AegisShared.realTime()
    -- a held client report was waiting exactly for this confirmation
    local h = held[name]
    if h then
        held[name] = nil
        writeReport(name, h.args, h.x, h.y, h.z)
        return
    end
    -- in solo the report can land before this event
    if lastReport[name] and now - lastReport[name] < THROTTLE then return end

    local facts = { epoch = now }
    facts.x, facts.y, facts.z = c:getX(), c:getY(), c:getZ()
    pcall(function()
        local sq = c:getCurrentSquare()
        if sq then
            local room = sq:getRoom()
            if room then facts.room = room:getName() end
            facts.zone = sq:getZoneType()
        end
    end)
    pcall(function()
        local a = c:getAttackedBy()
        if a then
            if a:isZombie() then facts.attacker = "zombie"
            elseif a:isAnimal() then facts.attacker = "animal"
            elseif instanceof(a, "IsoPlayer") then
                facts.attacker = "player " .. tostring(a:getUsername())
            end
        end
    end)
    facts.onFire = c:isOnFire()
    facts.hours = c:getHoursSurvived()
    facts.kills = c:getZombieKills()
    -- neighbours now, at flush time they have long moved on
    facts.near = nearbyLines(facts.x, facts.y, name)
    pending[name] = facts
end

Events.OnCharacterDeath.Add(onCharacterDeath)

local function flushPending()
    local now = AegisShared.realTime()
    local done = nil
    for name, facts in pairs(pending) do
        if now - facts.epoch >= NET_DELAY then
            done = done or {}
            table.insert(done, name)
            -- any report younger than the death makes the net obsolete
            if not (lastReport[name] and lastReport[name] >= facts.epoch - 5) then
                local t = {}
                table.insert(t, "Victim: " .. cap(name, 48))
                -- the file header stamps the flush time, the death was earlier
                table.insert(t, "Died: " .. AegisShared.timestampReadable(facts.epoch))
                table.insert(t, "Source: server safety net, no client report received")
                if facts.x then
                    table.insert(t, "Position: " .. math.floor(facts.x) .. ","
                        .. math.floor(facts.y or 0) .. "," .. math.floor(facts.z or 0))
                end
                if facts.room then table.insert(t, "Room: " .. cap(facts.room, 48)) end
                if facts.zone then table.insert(t, "Zone: " .. cap(facts.zone, 48)) end
                if facts.attacker then table.insert(t, "Attacker: " .. cap(facts.attacker, 64)) end
                if facts.onFire == true then table.insert(t, "On fire: yes") end
                if facts.hours then
                    table.insert(t, "Hours survived: "
                        .. tostring(math.floor((tonumber(facts.hours) or 0) * 10 + 0.5) / 10))
                end
                if facts.kills then table.insert(t, "Zombie kills: " .. tostring(facts.kills)) end
                if facts.near and #facts.near > 0 then
                    table.insert(t, "Players nearby (" .. NEAR_DIST .. " tiles):")
                    for _, line in ipairs(facts.near) do table.insert(t, "  " .. line) end
                end
                AegisLog.write("Deaths", name, name, table.concat(t, "\n"))
                notifyAdmins(name)
            end
        end
    end
    if done then
        for _, n in ipairs(done) do pending[n] = nil end
    end

    -- held reports: the sender may have died a moment after reporting
    -- (packet race) or have left; a player still alive and online past
    -- HOLD_MAX was never dying and the report is dropped
    for name, h in pairs(held) do
        local p = nil
        pcall(function()
            local players = getOnlinePlayers()
            if not players then return end
            for i = 0, players:size() - 1 do
                local q = players:get(i)
                if q and q:getUsername() == name then
                    p = q
                    break
                end
            end
        end)
        local dead = false
        if p then dead = p:isDead() == true end
        if dead then
            held[name] = nil
            writeReport(name, h.args, h.x, h.y, h.z)
        elseif not p then
            held[name] = nil
            writeReport(name, h.args, h.x, h.y, h.z,
                "player left before the server confirmed the death")
        elseif now - h.epoch > HOLD_MAX then
            held[name] = nil
            print("[Aegis] death report from living player dropped: " .. tostring(name))
        end
    end
end

Events.EveryOneMinute.Add(flushPending)

local function onClientCommand(module, command, player, args)
    if module ~= AegisShared.MODULE then return end
    -- suspended senders keep no authority in any Aegis area
    if AegisModeration.isSuspended(player) then return end
    if Commands[command] then Commands[command](player, args) end
end

Events.OnClientCommand.Add(onClientCommand)
