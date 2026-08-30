BetterPush = BetterPush or {}

BetterPush.MODULE = "BetterPush"
BetterPush.COMMAND_REQUEST = "Trigger"
BetterPush.COMMAND_SYNC = "Knockdown"
BetterPush.DOMINO_DELAY_TICKS = 20

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
---@param str number The player's current Strength perk level
---@return number The push chance (0-100)
function BetterPush.getChanceForStrength(str)
    local minStr = BetterPush.getMinStrengthLevel()
    local maxStr = BetterPush.getMaxStrengthLevel()
    local minChance = BetterPush.getMinChance()
    local maxChance = BetterPush.getMaxChance()

    if str < minStr then return 0 end
    if str >= maxStr then return maxChance end
    if minStr == maxStr then return maxChance end

    local t = (str - minStr) / (maxStr - minStr)
    return math.floor(minChance + t * (maxChance - minChance) + 0.5)
end

--- Calculate the maximum number of pushed zombies based on the player's current strength level.
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

--- Domino chain: starting from the shoved zombie, repeatedly pick the nearest
--- not-yet-used zombie that is both ahead of the previous link (dot product with the
--- player->shovedZombie direction) and within the lateral corridor - not just the
--- closest zombie in any direction. Skips zombies already knocked down.
---@param player IsoPlayer The player who shoved
---@param shovedZombie IsoZombie The zombie that was directly shoved
---@param maxCount number Maximum chain length
---@return table List of IsoZombie objects in chain order
function BetterPush.getDominoChain(player, shovedZombie, maxCount)
    local results = {}
    if not player or not shovedZombie or maxCount <= 0 then return results end

    local cell = player:getCell()
    if not cell then return results end

    -- Push direction: from player toward the shoved zombie.
    local dx = shovedZombie:getX() - player:getX()
    local dy = shovedZombie:getY() - player:getY()
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.1 then return results end
    local dirX, dirY = dx / dist, dy / dist

    local allZombies = cell:getZombieList()
    if not allZombies then return results end

    local stepDist = BetterPush.getLineDistance()
    local stepDistSq = stepDist * stepDist
    local lateralTolerance = BetterPush.getLineWidth()

    local used = { [shovedZombie] = true }
    local currentX, currentY, currentZ = shovedZombie:getX(), shovedZombie:getY(), shovedZombie:getZ()
    local currentFloor = math.floor(currentZ)

    for _ = 1, maxCount do
        local bestZombie, bestForward = nil, nil

        for i = 0, allZombies:size() - 1 do
            local z = allZombies:get(i)
            if z and not used[z] and not z:isDead()
                and not (z.isKnockedDown and z:isKnockedDown())
                and math.floor(z:getZ()) == currentFloor
            then
                local zdx = z:getX() - currentX
                local zdy = z:getY() - currentY
                local distSq = zdx * zdx + zdy * zdy
                -- Forward = how far ahead along the push direction; lateral = how far
                -- off to the side. Both computed against the ORIGINAL push direction so
                -- the whole chain keeps following one straight line.
                local forward = zdx * dirX + zdy * dirY
                local lateral = math.abs(zdx * dirY - zdy * dirX)

                if forward > 0.05 and distSq <= stepDistSq and lateral <= lateralTolerance then
                    if not bestForward or forward < bestForward then
                        bestZombie, bestForward = z, forward
                    end
                end
            end
        end

        if not bestZombie then break end
        table.insert(results, bestZombie)
        used[bestZombie] = true
        currentX, currentY = bestZombie:getX(), bestZombie:getY()
    end

    return results
end

--- Resolve a zombie by online ID, falling back to the nearest zombie at a reported
--- position if the ID hasn't resolved on this machine yet (online-ID propagation can
--- lag a tick or two behind position sync across the client/server boundary).
---@param x number
---@param y number
---@param z number
---@param onlineID number|nil
---@param cell IsoCell|nil
---@return IsoZombie|nil
function BetterPush.findZombie(x, y, z, onlineID, cell)
    cell = cell or getCell()
    local zombies = cell and cell:getZombieList()
    if not zombies then return nil end

    local targetFloor = math.floor(z or 0)
    local best, bestDistSq = nil, 2.25 -- 1.5-tile fallback radius

    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombie and not zombie:isDead() and math.floor(zombie:getZ()) == targetFloor then
            if onlineID and onlineID >= 0 and zombie:getOnlineID() == onlineID then
                return zombie
            end
            local dx, dy = zombie:getX() - x, zombie:getY() - y
            local distSq = dx * dx + dy * dy
            if distSq < bestDistSq then
                best, bestDistSq = zombie, distSq
            end
        end
    end

    return best
end

--- Knock down a zombie. Only setHitReaction + setKnockedDown - the two calls that
--- actually represent a domino knockdown (see LOCAL_CHANGES.md LS-002). The original
--- also called knockDown()/setStaggerBack()/setFallOnFront() speculatively "for
--- compatibility"; stacking multiple knockdown-variant setters on the same zombie
--- risked conflicting animation/state rather than helping.
---@param zombie IsoZombie
---@return boolean True if the zombie was knocked down by this call
function BetterPush.knockDownZombie(zombie)
    if not zombie or zombie:isDead() then return false end
    if zombie.isKnockedDown and zombie:isKnockedDown() then return false end

    local applied = false
    if zombie.setHitReaction then
        zombie:setHitReaction("Shove")
        applied = true
    end
    if zombie.setKnockedDown then
        zombie:setKnockedDown(true)
        applied = true
    end
    return applied
end
