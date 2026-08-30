if not (isServer and isServer()) then return end

require "CyesPushDoors/Core"

local CPD = CyesPushDoors
local C = CPD and CPD.Config or nil

if not CPD or CPD._serverDebugFileSinkInstalled == true then return end
CPD._serverDebugFileSinkInstalled = true

local FILE_NAME = "CPD_MP_SERVER_DEBUG.txt"
local writeFailureReported = false

local keptTags = {
    SERVER_LOAD = true,
    SERVER_RECEIVE = true,
    SERVER_VALIDATE = true,
    SERVER_IMPACT_SIDE_REJECT = true,
    SERVER_QUEUE = true,
    SERVER_QUEUE_SKIP = true,
    SERVER_FAST_RESOLVE = true,
    SERVER_STATE_WAIT = true,
    SERVER_RESOLVE_START = true,
    SERVER_RESOLVE_DROP = true,
    SERVER_RESOLVE_ERROR = true,
    SERVER_RESOLVE_END = true,
    SERVER_TARGETS = true,
    SERVER_ZOMBIE_RESULT = true,
    SERVER_ZOMBIE_SKIP = true,
    SERVER_SYNC_SKIP = true,
    SERVER_SYNC_BROADCAST = true,
    SERVER_SYNC_BROADCAST_OK = true,
    SERVER_SYNC_BROADCAST_FAIL = true,
    SERVER_VERIFY_750MS = true,
    SERVER_ACK = true,
    IMPACT_GEOMETRY = true,
    IMPACT_STRAIN_BLOCK = true,
    IMPACT_RECOVERY_BLOCK = true,
    IMPACT_RECOVERY_START = true,
    DOUBLE_DOOR_GROUP = true,
    TARGET_SCAN = true,
    TARGET_NEAR = true,
}

local function nowMs()
    if getTimestampMs then
        local ok, value = pcall(getTimestampMs)
        if ok and value ~= nil then return tostring(value) end
    end
    return tostring(os and os.time and (os.time() * 1000) or "unknown")
end

local function writeLine(line, append)
    if not getFileWriter then return false end

    local ok, err = pcall(function()
        local writer = getFileWriter(FILE_NAME, true, append == true)
        if not writer then error("getFileWriter returned nil") end
        writer:writeln(tostring(line or ""))
        writer:close()
    end)

    if not ok and not writeFailureReported then
        writeFailureReported = true
        print("[CPD SERVER FILE DEBUG] Could not write " .. FILE_NAME .. ": " .. tostring(err))
    end
    return ok
end

local function keepLogMessage(msg)
    msg = tostring(msg or "")
    if string.find(msg, "Player door impact", 1, true) then return true end
    if string.find(msg, "Resolved impact", 1, true) then return true end
    if string.find(msg, "Rejected door transition", 1, true) then return true end
    if string.find(msg, "Rejected scanner door transition", 1, true) then return true end
    if string.find(msg, "Server impact error", 1, true) then return true end
    return false
end

local function shouldKeep(tag, msg)
    tag = tostring(tag or "")
    if keptTags[tag] == true then return true end
    if tag == "LOG" then return keepLogMessage(msg) end
    return false
end

if C and C.DEBUG == true then
    writeLine("=== CPD MP SERVER DEBUG SESSION START ===", false)
    writeLine("timestampMs=" .. nowMs(), true)
    writeLine("debugLabel=" .. tostring(C.DEBUG_LABEL or C.VERSION or "DEBUG"), true)
    writeLine("file=" .. FILE_NAME, true)
    writeLine("=========================================", true)
end

CPD._serverDebugFileSink = function(tag, msg, renderedLine)
    if not C or C.DEBUG ~= true then return end
    if not shouldKeep(tag, msg) then return end

    local line = renderedLine
    if line == nil or tostring(line) == "" then
        line = "[CPD SERVER FILE][" .. tostring(tag) .. "] " .. tostring(msg)
    end

    writeLine(tostring(line), true)
end

if C and C.DEBUG == true then
    print("[CPD SERVER FILE DEBUG] Filtered diagnostics enabled: " .. FILE_NAME)
end
