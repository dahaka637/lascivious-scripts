local function getSandbox(key, fallback)
    if SandboxVars.SprintDiveWindows and SandboxVars.SprintDiveWindows[key] ~= nil then
        return SandboxVars.SprintDiveWindows[key]
    end
    return fallback
end

local function dbg(msg)
    if getSandbox("Debug", false) then
        print("[SprintDiveWindows] " .. tostring(msg))
    end
end

local function getWindowInfo(collider)
    if not collider then return nil end

    if instanceof(collider, "IsoWindow") then
        return { object = collider, kind = "window", north = collider:isNorth() }
    end

    if IsoWindowFrame.isWindowFrame(collider) then
        return { object = collider, kind = "frame", north = collider:getNorth() }
    end

    if instanceof(collider, "IsoThumpable") then
        local sprite = collider:getSprite()
        if not sprite then return nil end
        local props = sprite:getProperties()
        if not props then return nil end

        local isNorth = props:has(IsoFlagType.WindowN)
        if isNorth or props:has(IsoFlagType.WindowW) then
            return { object = collider, kind = "thumpable", north = isNorth }
        end
    end

    return nil
end

local function getDiveDirection(character, info)
    local square = info.object:getSquare()
    if not square then return nil end

    if info.north then
        if character:getY() < square:getY() then
            return IsoDirections.S
        end
        return IsoDirections.N
    end

    if character:getX() < square:getX() then
        return IsoDirections.E
    end
    return IsoDirections.W
end

local function canPassThrough(character, info)
    local obj = info.object

    if info.kind == "window" then
        return obj:canClimbThrough(character)
            or (not obj:isInvincible() and not obj:isBarricaded())
    elseif info.kind == "frame" then
        return IsoWindowFrame.canClimbThrough(obj, character)
    else
        return obj:canClimbThrough(character)
    end
end

local lastDiveMs = 0
local DIVE_COOLDOWN_MS = 1200

local pendingLanding = nil

local pendingOutcome = nil

local function bounceOffWindow(character)
    character:setSprinting(false)
    character:clearVariable("BumpFallType")
    character:setBumpType("stagger")
    character:setBumpDone(false)
    character:setBumpFall(true)
    character:setBumpFallType("pushedFront")
    character:reportEvent("wasBumped")
end

local function onObjectCollide(character, collider)
    if not instanceof(character, "IsoPlayer") then return end
    if not character:isSprinting() then return end
    if character:isCurrentState(ClimbOverFenceState.instance()) then return end
    if character:isCurrentState(ClimbThroughWindowState.instance()) then return end
    if character:getVariableBoolean("ClimbingFence") then return end
    if character:isBumpFall() then return end
    if character:isKnockedDown() then return end
    if character:isCurrentState(PlayerGetUpState.instance()) then return end

    local now = getTimestampMs()
    if (now - lastDiveMs) < DIVE_COOLDOWN_MS then return end

    local sprintTime = character:getBeenSprintingFor()
    local minSprintTime = getSandbox("MinSprintTime", 30)
    local shortSprint = sprintTime < minSprintTime

    local info = getWindowInfo(collider)
    if not info then return end

    local dir = getDiveDirection(character, info)
    if not dir then
        dbg("nao consegui determinar a direcao (square nulo)")
        return
    end

    if not canPassThrough(character, info) then
        dbg("janela bloqueada (barricada/invencivel) -- bateu e caiu")
        lastDiveMs = now
        bounceOffWindow(character)
        return
    end

    pendingLanding = nil
    local multiTileObstacle = false
    local charSquare = character:getSquare()
    if charSquare then
        local oppositeSq = charSquare:getAdjacentSquare(dir)
        if oppositeSq and ClimbThroughWindowState.isObstacleSquare(oppositeSq) then
            local afterSq = oppositeSq:getAdjacentSquare(dir)
            if not (afterSq and ClimbThroughWindowState.isFreeSquare(afterSq)) then
                multiTileObstacle = true
                local freeSq = ClimbThroughWindowState.getFreeSquareAfterObstacles(oppositeSq, dir)
                if freeSq then
                    pendingLanding = freeSq
                    dbg("movel de varios tiles depois da janela -- vai reposicionar em " .. tostring(freeSq:getX()) .. "," .. tostring(freeSq:getY()))
                else
                    dbg("movel de varios tiles e sem chao livre depois -- sem reposicionamento possivel")
                end
            end
        end
    end

    if shortSprint then
        dbg("sprint curto (" .. string.format("%.1f", sprintTime) .. " < " .. tostring(minSprintTime) .. ") -- vai bater na janela")
    else
        dbg("mergulho | sprintTime=" .. string.format("%.1f", sprintTime) .. " dir=" .. tostring(dir) .. " tipo=" .. info.kind .. " movelGrande=" .. tostring(multiTileObstacle))
    end
    lastDiveMs = now

    local hadGlass = false
    local mayBreakGlass = (not shortSprint) or getSandbox("ShortSprintBreaksGlass", true)

    if info.kind == "window" and mayBreakGlass then
        local window = info.object
        if not window:IsOpen() and not window:isSmashed() then
            window:smashWindow()
            window:addBrokenGlass(character)
            hadGlass = true
            dbg("vidro quebrado")
        elseif not window:isGlassRemoved() then
            hadGlass = true
        end
    elseif info.kind == "window" then
        dbg("impulso curto e a opcao de quebrar vidro esta desligada -- janela intacta, sem dano")
    end

    local failed = false
    if not shortSprint then
        local failChance = getSandbox("FailChance", 30)
        local failRoll = ZombRand(100)
        failed = failRoll < failChance
        dbg("chance de falha: roll " .. tostring(failRoll) .. " vs " .. tostring(failChance) .. " -> " .. (failed and "falhou" or "passou"))
    end

    if shortSprint or (failed and multiTileObstacle) then
        pendingLanding = nil
        pendingOutcome = nil
        if failed and multiTileObstacle then
            dbg("falhou com movel de varios tiles do outro lado -- bateu a cara e voltou")
        end
        bounceOffWindow(character)
    else
      
        local useCustomAnim = hadGlass and not getSandbox("VanillaAnimation", false)
        if useCustomAnim then
            character:setVariable("DiveThruWindow", true)
        end
        pendingOutcome = failed and "fall" or "success"

        if isClient() then
            local args = {}
            args.id = character:getOnlineID()
            args.outcome = pendingOutcome
            args.dive = useCustomAnim
            sendClientCommand(character, "SprintDiveWindows", "diveOutcome", args)
        end

        ClimbOverFenceState.instance():setParams(character, dir)
        if failed then
            character:set(ClimbOverFenceState.COUNTER, false)
        end

        character:reportEvent("EventClimbFence")
    end

    if hadGlass then
        local chance = getSandbox("InjuryChance", 60)
        local roll = ZombRand(100)
        if roll < chance then
            sendClientCommand(character, "SprintDiveWindows", "glassCut", {})
            dbg("corte de vidro (roll " .. tostring(roll) .. " < " .. tostring(chance) .. ") -- pedido enviado ao servidor")
        else
            dbg("sem corte (roll " .. tostring(roll) .. " >= " .. tostring(chance) .. ")")
        end
    end
end

Events.OnObjectCollide.Add(onObjectCollide)

local function onPlayerUpdate(player)
    if not player then return end

    local climbing = player:getVariableBoolean("ClimbingFence")
    if pendingOutcome and climbing then
        local current = player:getVariableString("ClimbFenceOutcome")
        if current == "success" or current == "fall" then
            if current ~= pendingOutcome then
                player:setVariable("ClimbFenceOutcome", pendingOutcome)
            end
        end
        pendingOutcome = nil
    end

    if player:getVariableBoolean("DiveThruWindow") and not climbing then
        player:clearVariable("DiveThruWindow")
    end
    if pendingLanding and not climbing then
        local target = pendingLanding
        pendingLanding = nil

        local sq = player:getSquare()
        if sq and ClimbThroughWindowState.isObstacleSquare(sq) then
            local x = target:getX() + 0.5
            local y = target:getY() + 0.5
            local z = target:getZ()

            player:setX(x)
            player:setNextX(x)
            player:setY(y)
            player:setNextY(y)

            player:setLastX(x)
            player:setLastY(y)
            player:setLastZ(z)

            if isClient() then
                local args = {}
                args.id = player:getOnlineID()
                args.x = x
                args.y = y
                args.z = z
                sendClientCommand(player, "SprintDiveWindows", "diveLanding", args)
            end

            if getSandbox("Debug", false) then
                print("[SprintDiveWindows] reposicionado para " .. tostring(target:getX()) .. "," .. tostring(target:getY()) .. " (estava em cima do movel)")
            end
        end
    end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)

dbg("Carregado.")
