if isClient() then
    return
end
local Commands = require "PhunZones/server_commands"
local Core = PhunZones
local getTimestamp = getTimestamp

PhunZonesEventRegistry = PhunZonesEventRegistry or {}
local oldHandlers = PhunZonesEventRegistry.server or {}
local handlers = {}
PhunZonesEventRegistry.server = handlers
Core._serverEventHandlers = handlers

local function removeHandler(event, fn)
    if event and fn and event.Remove then pcall(event.Remove, fn) end
end
removeHandler(Events.OnClientCommand, oldHandlers.clientCommand)
removeHandler(Events.OnServerStarted, oldHandlers.serverStarted)

local function onClientCommand(module, command, playerObj, arguments)
    if module ~= Core.name or type(command) ~= "string" or not playerObj then return end
    local handler = Commands[command]
    if handler then
        local ok, err = pcall(handler, playerObj, type(arguments) == "table" and arguments or {})
        if not ok then
            print("PhunZones: server command '" .. command .. "' failed: " .. tostring(err))
        end
    end
end
handlers.clientCommand = onClientCommand
Events.OnClientCommand.Add(onClientCommand)

local function onServerStarted()
    Core:ini()
end
handlers.serverStarted = onServerStarted
Events.OnServerStarted.Add(onServerStarted)

