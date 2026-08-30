--
-- Subir Escaleras - menu contextual
-- Build 42.20
--

-- Nada de esto tiene sentido en un servidor: ni hay menu contextual ni existe
-- el evento. Salimos antes de los require, que tambien son de cliente.
if isServer() then return end

require "TimedActions/WalkToTimedAction"
require "SubirEscaleras/SE_Utils"
require "SubirEscaleras/SE_ClimbAction"

local function makeTooltip(text)
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = text
    return tooltip
end

local function onClimb(worldobjects, playerNum, ladder, ladderSquare, startSquare, target, down)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    ISTimedActionQueue.clear(playerObj)
    if startSquare and playerObj:getCurrentSquare() ~= startSquare then
        ISTimedActionQueue.add(ISWalkToTimedAction:new(playerObj, startSquare))
    end
    ISTimedActionQueue.add(ISSubirEscaleraAction:new(playerObj, ladder, ladderSquare,
        startSquare, target, down))
end

--- Vuelca todo lo que haya en 3x3 casillas y 3 niveles alrededor de donde se
--- ha pinchado. Asi no hace falta acertar la casilla exacta de la escalera.
local function onDump(worldobjects, playerNum, square)
    local cell = getCell()
    local x0, y0, z0 = square:getX(), square:getY(), square:getZ()
    print(string.format("[SubirEscaleras] ===== volcado alrededor de %d,%d,%d =====", x0, y0, z0))

    local playerObj = getSpecificPlayer(playerNum)
    if playerObj then
        local ps = playerObj:getCurrentSquare()
        print(string.format("[SubirEscaleras] JUGADOR pos=%.2f,%.2f,%.2f cuadro=%s pisable=%s",
            playerObj:getX(), playerObj:getY(), playerObj:getZ(),
            ps and string.format("%d,%d,%d", ps:getX(), ps:getY(), ps:getZ()) or "nil",
            ps and tostring(SubirEscaleras.isStandable(ps)) or "nil"))
    end

    -- que ve el mod desde aqui
    local ladder, dir, ls = SubirEscaleras.findLadderNear(x0, y0, z0)
    if not ladder then ladder, dir, ls = SubirEscaleras.findLadderNear(x0, y0, z0 - 1) end
    if ladder and ls then
        print(string.format("[SubirEscaleras] ESCALERA en %d,%d,%d dir=%s",
            ls:getX(), ls:getY(), ls:getZ(), tostring(dir)))
        local up = SubirEscaleras.getTargetSquare(ls, false, dir)
        local down = SubirEscaleras.getTargetSquare(ls, true, dir)
        print(string.format("[SubirEscaleras] DESTINO subir=%s  bajar=%s",
            up and string.format("%d,%d,%d", up:getX(), up:getY(), up:getZ()) or "nil",
            down and string.format("%d,%d,%d", down:getX(), down:getY(), down:getZ()) or "nil"))
    else
        print("[SubirEscaleras] ESCALERA no encontrada cerca")
    end

    for dz = -1, 1 do
        for dy = -1, 1 do
            for dx = -1, 1 do
                local sq = cell:getGridSquare(x0 + dx, y0 + dy, z0 + dz)
                if sq then
                    print(string.format("[SubirEscaleras] %d,%d,%d | pisable=%s suelo=%s solido=%s",
                        sq:getX(), sq:getY(), sq:getZ(),
                        tostring(SubirEscaleras.isStandable(sq)),
                        tostring(sq:getFloor() ~= nil),
                        tostring(sq:isSolid())))
                    local objects = sq:getObjects()
                    for i = 0, objects:size() - 1 do
                        local object = objects:get(i)
                        local sprite = object:getSprite()
                        local name = sprite and sprite:getName()
                        if name then
                            print(string.format("[SubirEscaleras] %d,%d,%d | %s | trepable=%s",
                                sq:getX(), sq:getY(), sq:getZ(), name,
                                tostring(SubirEscaleras.getClimbDir(object))))
                        end
                    end
                end
            end
        end
    end
    print("[SubirEscaleras] ===== fin del volcado =====")
end

--- Distancia en casillas ignorando la altura.
local function isNearColumn(squareA, squareB, radius)
    radius = radius or 1
    return math.abs(squareA:getX() - squareB:getX()) <= radius
        and math.abs(squareA:getY() - squareB:getY()) <= radius
end

local function addUpOption(context, worldobjects, playerNum, playerSquare, ladder, dir, ladderSquare)
    local playerObj = getSpecificPlayer(playerNum)

    -- estado del personaje antes que nada: si no puede subir, da igual el destino
    local canClimb, reason = SubirEscaleras.canClimb(playerObj, false)
    if not canClimb then
        local blocked = context:addOption(getText("ContextMenu_SubirEscaleras_Up"), worldobjects, nil)
        blocked.notAvailable = true
        blocked.toolTip = makeTooltip(getText(reason))
        return
    end

    local target, exact = SubirEscaleras.getTargetSquare(ladderSquare, false, dir)

    if target then
        context:addOption(getText("ContextMenu_SubirEscaleras_Up"), worldobjects, onClimb, playerNum,
            ladder, ladderSquare, ladderSquare, target, false)
        return
    end

    local option = context:addOption(getText("ContextMenu_SubirEscaleras_Up"), worldobjects, nil)
    option.notAvailable = true
    if not exact then
        option.toolTip = makeTooltip(getText("IGUI_SubirEscaleras_SinNivel"))
    else
        option.toolTip = makeTooltip(getText("IGUI_SubirEscaleras_SinSalida"))
    end
end

local function addDownOption(context, worldobjects, playerNum, playerSquare, ladder, dir, ladderSquare)
    -- al bajar, el destino es el propio nivel de la escalera
    local target = SubirEscaleras.getTargetSquare(ladderSquare, true, dir)
    if not target then return end

    -- de donde salimos: lo alto de la escalera, al nivel del jugador. Aqui si
    -- valen los cuadros tapiados (ultimo argumento): el jugador ya esta arriba,
    -- solo se trata de acercarlo al hueco antes de bajar.
    local startSquare = SubirEscaleras.findLanding(ladderSquare:getX(), ladderSquare:getY(),
        playerSquare:getZ(), dir, true)
    if not startSquare then startSquare = playerSquare end

    context:addOption(getText("ContextMenu_SubirEscaleras_Down"), worldobjects, onClimb, playerNum,
        ladder, ladderSquare, startSquare, target, true)
end

--- Se llama dos veces: una con test=true y otra con test=false.
---
--- La pasada con test=true es como el juego pregunta "hay algo con lo que
--- interactuar aqui?". Si nadie contesta que si, el mando no abre el menu y el
--- jugador con controlador no ve nuestras opciones. Hay que contestar llamando
--- a ISWorldObjectContextMenu.setTest(), pero SIN anadir opciones todavia.
--- Ver el comentario de esa funcion en ISWorldObjectContextMenu.lua:122.
local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj or playerObj:isDead() then return end

    local playerSquare = playerObj:getCurrentSquare()
    if not playerSquare then return end

    local square = nil
    for _, object in ipairs(worldobjects) do
        if object:getSquare() then
            square = object:getSquare()
            break
        end
    end
    if not square then return end

    if SubirEscaleras.debug and not test then
        context:addOption(getText("ContextMenu_SubirEscaleras_Dump"), worldobjects, onDump, playerNum, square)
    end

    local z = playerSquare:getZ()

    --- Busca alrededor de donde se ha pinchado y, si ahi no hay nada, alrededor
    --- del propio jugador. Las escaleras altas pegadas al norte o al oeste
    --- dibujan su sprite lejos de su casilla real y son dificiles de acertar
    --- con el raton; si estas al lado de una, la opcion sale igual.
    local function findLadderAt(level, radius)
        local ladder, dir, ladderSquare = SubirEscaleras.findLadderNear(
            square:getX(), square:getY(), level, radius)
        if ladder then return ladder, dir, ladderSquare end

        return SubirEscaleras.findLadderNear(
            playerSquare:getX(), playerSquare:getY(), level, radius)
    end

    -- escalera a la altura del jugador -> subir
    local radioSubir = SubirEscaleras.searchRadius
    local ladder, dir, ladderSquare = findLadderAt(z, radioSubir)
    local hayEscaleraArriba = ladder and isNearColumn(playerSquare, ladderSquare, radioSubir)

    -- Escalera un nivel por debajo -> bajar. Se busca mas lejos a proposito:
    -- la escalera esta oculta bajo el suelo, no se ve, y con radio 1 la opcion
    -- no aparecia casi nunca. Es el fallo que reportaron los usuarios.
    local radioBajar = SubirEscaleras.downSearchRadius
    local ladderD, dirD, ladderSquareD = findLadderAt(z - 1, radioBajar)
    local hayEscaleraAbajo = ladderD and isNearColumn(playerSquare, ladderSquareD, radioBajar)

    -- pasada de prueba: solo contestamos si hay algo, sin anadir nada
    if test then
        if hayEscaleraArriba or hayEscaleraAbajo then
            return ISWorldObjectContextMenu.setTest()
        end
        return
    end

    if hayEscaleraArriba then
        addUpOption(context, worldobjects, playerNum, playerSquare, ladder, dir, ladderSquare)
    end

    if hayEscaleraAbajo then
        addDownOption(context, worldobjects, playerNum, playerSquare, ladderD, dirD, ladderSquareD)
    end
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
