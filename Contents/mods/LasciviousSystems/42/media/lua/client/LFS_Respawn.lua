-- Lascivious Factions System - faction respawn (client side).
--
-- On death, drop the player back inside their faction's claim at the saved
-- respawn point (else the claim centroid).
--
-- This MUST run client-side: OnPlayerDeath and OnCreatePlayer are client events
-- (the game registers them only in client lua; they do not fire in a dedicated /
-- coop-host server process), so a server-side handler never runs on a hosted game.
-- Here both events fire for the local player, and the client can teleport its own
-- character. We record the death by username and consume it on the next character
-- creation, so first spawns and relogs are left in place and only a genuine
-- death-respawn relocates.
--
-- Two things that bit us: (1) the teleport must use player:teleportTo(x,y,z) --
-- setLx/setLy do NOT exist and threw "call nil"; (2) after death+character
-- creation the engine places the new character at the town spawn ASYNCHRONOUSLY
-- over several ticks, overwriting a single teleport, so we RE-APPLY over a handful
-- of ticks until it holds (the pattern the Safehouse mod uses).

require "LFS_Shared"
require "LFS_Localization"

local FF = LasciviousFactionsSystem

FF._respawnPending = type(FF._respawnPending) == "table" and FF._respawnPending or {}
local pending = FF._respawnPending   -- [username] = true, set on death, consumed on next create

local function onFactionPlayerDeath(playerObj)
    local uname = playerObj and playerObj.getUsername and playerObj:getUsername()
    if uname then
        pending[uname] = true
        -- The server owns the persisted score record, including the sandbox choice
        -- between resetting character power on death or preserving the member's
        -- already-contributed power.
        sendClientCommand(playerObj, FF.MODULE, "resetScoreOnDeath", {})
    end
end

local function onFactionCreatePlayer(playerIndex)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    local uname = player:getUsername()
    if not pending[uname] then return end   -- not a death-respawn; leave them be
    pending[uname] = nil

    if not FF.getOptions().respawnEnabled then return end

    local _, faction = FF.getFactionOfPlayer(uname)
    if not (faction and faction.claims and #faction.claims > 0) then return end

    local x, y, z
    if faction.respawn then
        x, y, z = faction.respawn.x, faction.respawn.y, faction.respawn.z
    else
        x, y = FF.claimCentroid(faction)
        z = 0
    end
    if not (x and y) then return end
    x, y, z = x + 0.5, y + 0.5, z or 0

    -- Re-apply the teleport over several ticks: the engine finalises the town
    -- spawn position asynchronously right after OnCreatePlayer, so a single
    -- teleportTo loses the race. We nudge it back for ~6 rounds until it sticks.
    local rounds, gap, ticks, done, teleportOk = 6, 10, 0, false, false
    local function apply()
        if done then Events.OnTick.Remove(apply); return end
        ticks = ticks - 1
        if ticks > 0 then return end
        ticks = gap
        local p = getSpecificPlayer(playerIndex)
        if not (p and p:getUsername() == uname and p.teleportTo) then
            done = true; Events.OnTick.Remove(apply); return
        end
        if pcall(function() p:teleportTo(x, y, z) end) then teleportOk = true end
        rounds = rounds - 1
        if rounds <= 0 then
            done = true
            Events.OnTick.Remove(apply)
            if not teleportOk then
                FF.warn(string.format("respawn teleport never succeeded for %s after 6 attempts "
                    .. "(player may be stuck at the town spawn instead of their faction claim)", uname))
            end
            if HaloTextHelper then
                local hok, herr = pcall(function()
                    HaloTextHelper.addText(p, FF.tr("Respawned at faction point"))
                end)
                if not hok then FF.warn("respawn halo text failed: " .. tostring(herr)) end
            end
            FF.log(string.format("respawned %s at faction point (%d,%d)", uname, math.floor(x), math.floor(y)))
        end
    end
    Events.OnTick.Add(apply)
end

if FF._respawnDeathHook then Events.OnPlayerDeath.Remove(FF._respawnDeathHook) end
if FF._respawnCreateHook then Events.OnCreatePlayer.Remove(FF._respawnCreateHook) end
FF._respawnDeathHook = onFactionPlayerDeath
FF._respawnCreateHook = onFactionCreatePlayer
Events.OnPlayerDeath.Add(onFactionPlayerDeath)
Events.OnCreatePlayer.Add(onFactionCreatePlayer)
