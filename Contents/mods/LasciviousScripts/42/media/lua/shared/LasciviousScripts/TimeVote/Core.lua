-- Lascivious Scripts - Multiplayer Time Vote
-- Shared protocol/constants. The custom panel only handles voting/presentation;
-- a granted multiplier is applied once; it is never reasserted. Native MP-active
-- reset paths are observed, while only the single-player reset gates disabled by
-- GameClient are mirrored on the client.

LasciviousScripts = LasciviousScripts or {}
LasciviousScripts.TimeVote = LasciviousScripts.TimeVote or {}

local Core = LasciviousScripts.TimeVote

Core.VERSION = "2.2.0"
Core.OPTION_TABLE = "LasciviousScriptsTimeVote"

Core.MODULE = "LasciviousScriptsTimeVote"
Core.CMD_HELLO = "hello"
Core.CMD_VOTE = "vote"
Core.CMD_CANCEL = "cancel"
Core.CMD_SYNC = "sync"

Core.NORMAL = 1
Core.FAST_FORWARD_MIN = 2
Core.MAX_SPEED = 4

-- Native speed levels exposed by SpeedControls: 1=play, 2=fast, 3=faster, 4=wait.
Core.MULT = { [1] = 1, [2] = 5, [3] = 20, [4] = 40 }

Core.DEFAULTS = { Enabled = true, SoloOnly = false, DebugLogging = false }

local function getLiveOption(name, fallback)
    local fullName = Core.OPTION_TABLE .. "." .. name
    local options = getSandboxOptions and getSandboxOptions() or nil
    if options then
        local option = options:getOptionByName(fullName)
        if option then
            local value = option:getValue()
            if value ~= nil then return value end
        end
    end

    local tableVars = SandboxVars and SandboxVars[Core.OPTION_TABLE] or nil
    if tableVars and tableVars[name] ~= nil then return tableVars[name] end
    return fallback
end

function Core.getConfig()
    return {
        Enabled = getLiveOption("Enabled", Core.DEFAULTS.Enabled) == true,
        SoloOnly = getLiveOption("SoloOnly", Core.DEFAULTS.SoloOnly) == true,
        DebugLogging = getLiveOption("DebugLogging", Core.DEFAULTS.DebugLogging) == true,
    }
end

function Core.log(message)
    print("[LasciviousScripts/TimeVote] " .. tostring(message))
end

function Core.debugLog(message)
    if Core.getConfig().DebugLogging then print("[LasciviousScripts/TimeVote][dbg] " .. tostring(message)) end
end

function Core.isValidSpeed(level)
    return type(level) == "number" and level == math.floor(level) and level >= Core.NORMAL and level <= Core.MAX_SPEED
end

function Core.multiplierFor(level)
    return Core.MULT[level] or 1
end

function Core.speedLabel(level)
    return tostring(Core.multiplierFor(level)) .. "x"
end

return Core
