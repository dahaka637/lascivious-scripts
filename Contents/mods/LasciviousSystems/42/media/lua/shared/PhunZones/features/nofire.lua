local Core = PhunZones

function Core.checkFire(fire)
    if not fire then return end
    local okSquare, square = pcall(function() return fire:getSquare() end)
    if not okSquare or not square then return end
    local zone = Core.getLocation(square) or {}
    local extinguish = zone.nofire == true

    if extinguish then
        local options, fireSpread
        local okOptions = pcall(function()
            options = getSandboxOptions()
            local option = options and options:getOptionByName("FireSpread")
            fireSpread = option and option:getValue()
        end)
        if not okOptions or not options or fireSpread == nil then return end

        local ok, err = pcall(function()
            options:set("FireSpread", false)
            Core.debugLn("NoFire zone detected, extinguishing fire. Fire spread is currently set to " ..
                             tostring(fireSpread))
            local moving = square:getMovingObjects()
            for i = 0, moving:size() - 1 do
                local chr = moving:get(i)
                if instanceof(chr, "IsoGameCharacter") and chr:isOnFire() then
                    if not isServer() then
                        if chr.sendStopBurning then chr:sendStopBurning() end
                        chr:StopBurning()
                    else
                        stopFire(chr)
                    end
                end
            end

            if not isServer() then
                square:transmitStopFire()
                square:stopFire()
            else
                stopFire(square)
            end
        end)
        -- FireSpread e global: restaura mesmo se qualquer API de fogo falhar.
        local restored, restoreErr = pcall(function() options:set("FireSpread", fireSpread) end)
        if not ok then
            print("PhunZones: error extinguishing nofire-zone fire: " .. tostring(err))
        end
        if not restored then
            print("PhunZones: error restoring FireSpread: " .. tostring(restoreErr))
        end
    end

end
