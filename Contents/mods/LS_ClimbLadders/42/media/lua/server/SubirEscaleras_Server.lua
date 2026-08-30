--
-- Subir Escaleras - lado servidor
-- Build 42.20
--
-- En multijugador el cliente no puede moverse a si mismo: el juego base nunca
-- llama a teleportTo en un cliente, siempre se lo pide al servidor
-- (ver ISAdminMessage.lua:81-85). Aqui recibimos esa peticion y la ejecutamos.
--
-- IMPORTANTE: esto es una orden que puede mandar cualquier cliente, asi que
-- hay que validarla. Sin limites seria un teletransporte libre para cualquiera
-- con el mod instalado y un poco de mala idea.
--

local MODULE = "SubirEscaleras"
local Geometry = require "SubirEscaleras/SE_ServerGeometry"

-- Ponlo en true para registrar cada trepada en el log del servidor.
-- Apagado por defecto: en un servidor con gente seria una linea por subida.
local DEBUG = false

local requestGate = {}
local REQUEST_MS = 750

local function integer(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    if value ~= math.floor(value) then return nil end
    return value
end

local function throttled(player)
    local name = tostring(player and (player:getUsername() or player:getOnlineID()) or "?")
    local now = getTimestampMs and getTimestampMs() or math.floor(os.time()*1000)
    if (requestGate[name] or 0) > now then return true end
    requestGate[name] = now + REQUEST_MS
    return false
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end
    if command ~= "requestClimb" or type(args) ~= "table" or not player then return end
    if throttled(player) then return end
    local x, y, z = integer(args.ladderX), integer(args.ladderY), integer(args.ladderZ)
    if not x or not y or not z or z < 0 or z > 31 then return end
    local down = args.down == true
    local expectedZ = math.floor(player:getZ()) - (down and 1 or 0)
    local radius = down and 2 or 1
    if z ~= expectedZ or math.abs(player:getX()-(x+0.5)) > radius+0.75
        or math.abs(player:getY()-(y+0.5)) > radius+0.75 then return end

    local ladderSquare = getCell():getGridSquare(x, y, z)
    local ladder, dir = Geometry.findLadder(ladderSquare)
    if not ladder then return end
    local target = Geometry.target(ladderSquare, down, dir)
    if not target then return end
    local tx, ty, tz = target:getX()+0.5, target:getY()+0.5, target:getZ()

    if DEBUG then
        print(string.format("[SubirEscaleras] servidor: %s -> %.2f,%.2f,%.2f",
            tostring(player:getUsername()), tx, ty, tz))
    end

    local levels = math.max(1, math.abs(tz-math.floor(player:getZ())))
    player:teleportTo(tx, ty, tz)
    pcall(function() player:getStats():remove(CharacterStat.ENDURANCE, 0.03*levels) end)

    -- En PZ la posicion de cada jugador es autoritativa en SU cliente, y los
    -- demas la interpolan de los paquetes de movimiento. Un cambio de nivel no
    -- viaja por ahi, asi que quien lo mira sigue viendo al otro abajo andando.
    -- Hay que avisar a todos explicitamente.
    sendServerCommand(MODULE, "climbed", {
        user = player:getUsername(),
        x = tx,
        y = ty,
        z = tz,
    })
end

Events.OnClientCommand.Add(onClientCommand)
