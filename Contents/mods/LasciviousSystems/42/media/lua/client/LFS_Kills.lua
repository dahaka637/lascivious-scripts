-- Lascivious Factions System - native character-stat reporting (client side).
--
-- The vanilla getZombieKills()/getHoursSurvived() values are the source of truth.
-- Every report is an ABSOLUTE snapshot of the current character, never a delta.
-- This matters when LFS is installed on an existing save: the very first report
-- imports all kills/hours the character already had instead of treating them as a
-- baseline and throwing them away. The same vanilla counters reset on a genuinely
-- new character; the server decides from sandbox config whether that replaces the
-- dead character's score or only re-anchors the new life and preserves old power.
--
-- Like the permission/friendly-fire hooks elsewhere in this mod, this is
-- ADVISORY and spoofable: the server credits the caller's OWN account and
-- sanity-clamps each report (see LFS_Server.lua's syncCharacterScore handler), but a
-- modified client could still inflate its own numbers. There is no stronger
-- authority available for a moment-to-moment stat like this without the
-- server independently re-simulating combat, which this mod does not do. The
-- server also reads the same methods from its IsoPlayer whenever available.
--
-- Reporting runs regardless of faction membership -- a player's score is
-- their current character's running total (data.playerScore), and only gets SUMMED into a
-- faction's strength once they are a member (see FF.factionScore). Tracking
-- from the start means joining a faction counts kills/hours earned before the
-- join, not just from that point forward.

require "LFS_Shared"

local FF = LasciviousFactionsSystem

if isServer() then return end

local broken = false                  -- set true after a failure; stop trying
local lastKills, lastHours = nil, nil -- last absolute snapshot successfully sent
local nextPoll = 0
local POLL_INTERVAL = 5               -- seconds between polls

-- Send the complete native state. Repeating an unchanged snapshot is unnecessary,
-- but zero is significant: after death/new-character it must overwrite the old cache.
local function syncScore(player, kills, hours)
    if lastKills == kills and lastHours == hours then return end
    sendClientCommand(player, FF.MODULE, "syncCharacterScore", {
        kills = kills,
        hours = hours,
    })
    lastKills, lastHours = kills, hours
end

-- Poll the local player's native counters and report their current absolute values.
local function pollScore()
    if broken then return end
    local now = getTimestamp()
    if now < nextPoll then return end
    nextPoll = now + POLL_INTERVAL

    local ok, err = pcall(function()
        local player = getPlayer()
        if not (player and player.getZombieKills and player.getHoursSurvived) then return end
        if player.isDead and player:isDead() then return end
        local kills = math.max(0, math.floor(tonumber(player:getZombieKills()) or 0))
        local hours = math.max(0, tonumber(player:getHoursSurvived()) or 0)
        syncScore(player, kills, hours)
    end)
    if not ok then
        broken = true
        FF.warn("score polling failed: " .. tostring(err)
            .. " (faction score reporting disabled)")
    end
end

-- A created/reloaded character must always send one full snapshot immediately.
-- For a respawn this is normally {0,0}; for an old save it is the complete history.
local function onCreatePlayer(index)
    lastKills, lastHours = nil, nil
    nextPoll = 0
end

if FF._scorePollHook then Events.OnTick.Remove(FF._scorePollHook) end
if FF._scoreCreatePlayerHook and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Remove(FF._scoreCreatePlayerHook)
end
FF._scorePollHook = pollScore
FF._scoreCreatePlayerHook = onCreatePlayer
Events.OnTick.Add(pollScore)
if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(onCreatePlayer) end
