-- Ferramentas administrativas de diagnostico/recuperacao. Permanecem inertes
-- por padrao e so aceitam chamadas quando HardcoreKitsConfig.DebugToolsEnabled
-- esta ligado (computado em HardcoreKits_SandboxBridge.lua a partir de
-- singleplayer de verdade + LasciviousFactionsSystem.Debug no sandbox -- nunca
-- verdadeiro numa sessao MP de verdade) E o remetente passa pela verificacao
-- autoritativa de admin.
--
-- Uso (console de debug F11, ou um script de teste temporario no cliente):
--   sendClientCommand(getPlayer(), "HKits", "debugState", {})
--   sendClientCommand(getPlayer(), "HKits", "debugResetAccount", {})
--
if isClient() then return end

require "HardcoreKits_Protocol"
require "HardcoreKits_Config"
require "HardcoreKits_Identity"
require "HardcoreKits_Persistence"
require "HardcoreKits_State"

local function toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, HardcoreKits.MODULE, command, args)
    else
        triggerEvent("OnServerCommand", HardcoreKits.MODULE, command, args)
    end
end

local DebugCommands = {}

DebugCommands[HardcoreKits.CMD_DEBUG_STATE] = function(player, args)
    local accountId = HardcoreKitsIdentity.accountId(player)
    local state = HardcoreKitsState.build(player, accountId)
    state.debugAccountId = accountId
    print("[HardcoreKits][debug] state de " .. HardcoreKitsIdentity.username(player) .. ": " .. tostring(accountId))
    toClient(player, HardcoreKits.CMD_DEBUG_REPLY, state)
end

DebugCommands[HardcoreKits.CMD_DEBUG_RESET_ACCOUNT] = function(player, args)
    local accountId = HardcoreKitsIdentity.accountId(player)
    local md = player and player:getModData()
    if md then md.HardcoreKits = nil end
    HardcoreKitsPersistence.resetAccount(accountId)
    print("[HardcoreKits][debug] reset completo (personagem + conta) para " .. HardcoreKitsIdentity.username(player))
    toClient(player, HardcoreKits.CMD_DEBUG_REPLY, HardcoreKitsState.build(player, accountId))
end

local function onClientCommand(module, command, player, args)
    if module ~= HardcoreKits.MODULE then return end
    if HardcoreKitsConfig.DebugToolsEnabled ~= true then return end
    if type(command) ~= "string" or #command > 64 then return end
    local handler = DebugCommands[command]
    if not handler then return end
    if not HardcoreKitsIdentity.isAdmin(player) then
        print("[HardcoreKits][debug] comando '" .. tostring(command) .. "' negado (nao-admin): "
            .. HardcoreKitsIdentity.username(player))
        return
    end
    local safeArgs = type(args) == "table" and args or {}
    local ok, err = pcall(handler, player, safeArgs)
    if not ok then
        print("[HardcoreKits][debug] erro no comando '" .. tostring(command) .. "': " .. tostring(err))
    end
end

if HardcoreKits._debugCommandHandler and Events.OnClientCommand.Remove then
    Events.OnClientCommand.Remove(HardcoreKits._debugCommandHandler)
end
HardcoreKits._debugCommandHandler = onClientCommand
Events.OnClientCommand.Add(onClientCommand)
