--
-- Subir Escaleras - sincronizacion en multijugador
-- Build 42.20
--
-- En PZ la posicion de un jugador es autoritativa en su propio cliente, y el
-- resto la interpola de los paquetes de movimiento. Un cambio de nivel no
-- viaja por ese canal: el que trepa se ve subir, pero los demas le siguen
-- viendo abajo andando.
--
-- El servidor nos avisa de cada trepada y aqui recolocamos al jugador ajeno
-- a mano.
--

if isServer() then return end

require "SubirEscaleras/SE_Utils"

local MODULE = "SubirEscaleras"

local function findOnlinePlayer(username)
    local players = getOnlinePlayers()
    if not players then return nil end

    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player and player:getUsername() == username then
            return player
        end
    end

    return nil
end

local function onServerCommand(module, command, args)
    if module ~= MODULE then return end
    if command ~= "climbed" then return end
    if not args or not args.user then return end

    local localPlayer = getSpecificPlayer(0)
    if localPlayer and localPlayer:getUsername() == args.user then
        -- a nosotros ya nos movio nuestro propio cliente
        return
    end

    local other = findOnlinePlayer(args.user)
    if not other then return end

    local square = getCell():getGridSquare(math.floor(args.x), math.floor(args.y), args.z)
    if square then
        pcall(function() other:setCurrent(square) end)
    end

    other:setX(args.x)
    other:setY(args.y)
    other:setZ(args.z)

    if SubirEscaleras.debug then
        print(string.format("[SubirEscaleras] sync: %s recolocado en %.2f,%.2f,%.2f",
            tostring(args.user), args.x, args.y, args.z))
    end
end

Events.OnServerCommand.Add(onServerCommand)
