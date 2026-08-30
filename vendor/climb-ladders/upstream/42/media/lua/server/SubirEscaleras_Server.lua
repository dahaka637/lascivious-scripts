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

-- Ponlo en true para registrar cada trepada en el log del servidor.
-- Apagado por defecto: en un servidor con gente seria una linea por subida.
local DEBUG = false

-- Cuanto puede alejarse el destino de donde esta el jugador. Una escalera
-- mueve como mucho un cuadro en horizontal y unos pocos niveles en vertical.
local MAX_HORIZONTAL = 2
local MAX_VERTICAL = 8

local function isReasonable(player, x, y, z)
    if not player then return false end

    local dx = math.abs(player:getX() - x)
    local dy = math.abs(player:getY() - y)
    local dz = math.abs(player:getZ() - z)

    if dx > MAX_HORIZONTAL or dy > MAX_HORIZONTAL then return false end
    if dz > MAX_VERTICAL then return false end
    if z < 0 or z > 31 then return false end

    return true
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then return end
    if command ~= "climb" then return end
    if not args or not args.x or not args.y or not args.z then return end

    if not isReasonable(player, args.x, args.y, args.z) then
        print(string.format("[SubirEscaleras] destino rechazado para %s: %.1f,%.1f,%.1f",
            tostring(player:getUsername()), args.x, args.y, args.z))
        return
    end

    if DEBUG then
        print(string.format("[SubirEscaleras] servidor: %s -> %.2f,%.2f,%.2f",
            tostring(player:getUsername()), args.x, args.y, args.z))
    end

    player:teleportTo(args.x, args.y, args.z)

    -- En PZ la posicion de cada jugador es autoritativa en SU cliente, y los
    -- demas la interpolan de los paquetes de movimiento. Un cambio de nivel no
    -- viaja por ahi, asi que quien lo mira sigue viendo al otro abajo andando.
    -- Hay que avisar a todos explicitamente.
    sendServerCommand(MODULE, "climbed", {
        user = player:getUsername(),
        x = args.x,
        y = args.y,
        z = args.z,
    })
end

Events.OnClientCommand.Add(onClientCommand)
