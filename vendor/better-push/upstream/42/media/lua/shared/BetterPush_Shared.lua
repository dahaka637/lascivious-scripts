BetterPush = BetterPush or {}

-- Getters for Sandbox Options (with fallback defaults)
function BetterPush.getMinStrengthLevel() return SandboxVars.BetterPush and SandboxVars.BetterPush.MinStrengthLevel or 5 end
function BetterPush.getMaxStrengthLevel() return SandboxVars.BetterPush and SandboxVars.BetterPush.MaxStrengthLevel or 10 end
function BetterPush.getMinChance() return SandboxVars.BetterPush and SandboxVars.BetterPush.MinChance or 5 end
function BetterPush.getMaxChance() return SandboxVars.BetterPush and SandboxVars.BetterPush.MaxChance or 30 end
function BetterPush.getMinZombies() return SandboxVars.BetterPush and SandboxVars.BetterPush.BetterPushMinZombies or 1 end
function BetterPush.getMaxZombies() return SandboxVars.BetterPush and SandboxVars.BetterPush.BetterPushMaxZombies or 4 end
function BetterPush.getLineDistance() return SandboxVars.BetterPush and SandboxVars.BetterPush.BetterPushLineDistance or 0.8 end
function BetterPush.getLineWidth() return SandboxVars.BetterPush and SandboxVars.BetterPush.BetterPushLineWidth or 0.8 end

--- Calculate the push chance based on the player's current strength level.
--- Linearly interpolates between MinChance and MaxChance across the
--- [MinStrengthLevel, MaxStrengthLevel] range.
--- Below MinStrengthLevel: returns 0 (cannot trigger).
--- At or above MaxStrengthLevel: returns MaxChance.
--- If min and max strength are the same, returns MaxChance at that level.
---@param str number The player's current Strength perk level
---@return number The push chance (0-100)
function BetterPush.getChanceForStrength(str)
    local minStr = BetterPush.getMinStrengthLevel()
    local maxStr = BetterPush.getMaxStrengthLevel()
    local minChance = BetterPush.getMinChance()
    local maxChance = BetterPush.getMaxChance()

    -- Below minimum strength: no chance
    if str < minStr then return 0 end

    -- At or above maximum strength: full max chance
    if str >= maxStr then return maxChance end

    -- Same min/max strength: flat chance at that level
    if minStr == maxStr then return maxChance end

    -- Linear interpolation between min and max
    local t = (str - minStr) / (maxStr - minStr)
    return math.floor(minChance + t * (maxChance - minChance) + 0.5)
end


--- Calculate the maximum number of pushed zombies based on the player's current strength level.
--- Linearly interpolates between MinZombies and MaxZombies across the
--- [MinStrengthLevel, MaxStrengthLevel] range.
---@param str number The player's current Strength perk level
---@return number The max number of pushed zombies
function BetterPush.getMaxZombiesForStrength(str)
    local minStr = BetterPush.getMinStrengthLevel()
    local maxStr = BetterPush.getMaxStrengthLevel()
    local minZ = BetterPush.getMinZombies()
    local maxZ = BetterPush.getMaxZombies()

    if str < minStr then return minZ end
    if str >= maxStr then return maxZ end
    if minStr == maxStr then return maxZ end

    local t = (str - minStr) / (maxStr - minStr)
    return math.floor(minZ + t * (maxZ - minZ) + 0.5)
end


--- Domino chain: from the shoved zombie, follow the push direction
--- and find the closest zombie near each "link" in the chain.
--- Each zombie in the chain must be within stepDist of the previous one
--- and roughly in the push direction (within lateralTolerance).
---@param player IsoPlayer The player who shoved
---@param shovedZombie IsoZombie The zombie that was directly shoved
---@param maxCount number Maximum chain length
---@return table List of IsoZombie objects in chain order
function BetterPush.getDominoChain(player, shovedZombie, maxCount)
    local results = {}
    local cell = player:getCell()
    if not cell then return results end

    -- Push direction: from player toward the shoved zombie
    local dx = shovedZombie:getX() - player:getX()
    local dy = shovedZombie:getY() - player:getY()
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.1 then return results end
    local dirX = dx / dist
    local dirY = dy / dist

    local allZombies = cell:getZombieList()
    if not allZombies then return results end

    -- How far each domino "step" can reach (tight = realistic chain)
    local stepDist = BetterPush.getLineDistance()  -- default 0.8 tiles
    local lateralTolerance = BetterPush.getLineWidth()  -- default 0.6 tiles

    -- Track which zombies are already in the chain
    local used = {}
    used[shovedZombie] = true

    -- Start the chain from the shoved zombie
    local currentX = shovedZombie:getX()
    local currentY = shovedZombie:getY()
    local currentZ = shovedZombie:getZ()

    for step = 1, maxCount do
        -- Find the closest zombie to the current one (must be nearly touching)
        local bestZombie = nil
        local bestDist = stepDist  -- zombies must be within this distance to chain

        for i = 0, allZombies:size() - 1 do
            local z = allZombies:get(i)
            if z and not used[z] and not z:isDead() and z:getZ() == currentZ then
                local zdx = z:getX() - currentX
                local zdy = z:getY() - currentY
                local zdist = math.sqrt(zdx * zdx + zdy * zdy)

                if zdist < bestDist then
                    bestZombie = z
                    bestDist = zdist
                end
            end
        end

        if bestZombie then
            table.insert(results, bestZombie)
            used[bestZombie] = true
            -- Next chain link starts from THIS zombie's position
            currentX = bestZombie:getX()
            currentY = bestZombie:getY()
        else
            -- Chain breaks - no zombie close enough
            break
        end
    end

    return results
end


--- Knock down a zombie using available methods.
--- Tries multiple approaches for compatibility.
---@param zombie IsoZombie
function BetterPush.knockDownZombie(zombie)
    if not zombie or zombie:isDead() then return end

    -- Method 1: setHitReaction to Shove (this is what the game does internally)
    if zombie.setHitReaction then
        zombie:setHitReaction("Shove")
    end

    -- Method 2: knockDown if available
    if zombie.knockDown then
        zombie:knockDown(true)
    end

    -- Method 3: setKnockedDown if available
    if zombie.setKnockedDown then
        zombie:setKnockedDown(true)
    end

    -- Method 4: setStaggerBack if available
    if zombie.setStaggerBack then
        zombie:setStaggerBack(true)
    end

    -- Method 5: setFallOnFront if available
    if zombie.setFallOnFront then
        zombie:setFallOnFront(true)
    end

    print("[BetterPush] Knocked down zombie at " .. zombie:getX() .. ", " .. zombie:getY())
end
