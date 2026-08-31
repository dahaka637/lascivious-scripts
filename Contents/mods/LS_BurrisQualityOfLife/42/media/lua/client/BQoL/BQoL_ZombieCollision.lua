--[[
    Burris Quality of Life -- zombies stop phasing through each other.

    Vanilla zombies overlap freely when they bunch up on the way to a target,
    which is how a horde collapses into what looks like one zombie with
    twelve arms. This feature gives zombies near the player a soft personal
    space: each tick, pairs closer than ZombieCollisionPushRadius are nudged
    apart through IsoMovingObject.setX/setY (verified public in the shipped
    42.20 jar).

    Cost stays flat regardless of horde size: only zombies within
    ZombieCollisionScanRadius of the player are even distance-checked, and
    only the nearest ZombieCollisionMaxZombies of those enter the pairwise
    pass. With the default cap of 12 the pairwise pass is 66 distance checks
    a tick -- unmeasurable.

    Multiplayer: disabled deliberately. This feature nudges zombies with
    IsoMovingObject.setX/setY while they are often chasing a player; in B42 MP
    zombies have network ownership, and writing X/Y for a remote zombie can
    fight server/client reconciliation and path/anims. Keep the soft spacing
    behaviour for SP only until a proper owner-aware MP design exists.

    Dead and other-floor zombies are skipped. The dead still collide in
    vanilla (they are corpses, not obstacles); pushing them would just drag
    bodies around.
]]

require "BQoL/BQoL_Core"
require "BQoL/BQoL_ZombieCollisionLogic"

local ZombieCollision = BQoL.ZombieCollision
local warnedMPDisabled = false

-- ------------------------------------------------------------ candidate set

--- True when the zombie should take part this tick.
local function isCandidate(zombie, playerZ, scope)
    local ok, dead = BQoL.safe("ZCollision.isDead", function()
        return zombie:isDead() end)
    if ok and dead then return false end

    local ok2, z = BQoL.safe("ZCollision.getZ", function()
        return zombie:getZ() end)
    if not ok2 or z ~= playerZ then return false end

    local hasTarget, targetIsPlayer = false, false
    if scope ~= 3 then
        local ok3, target = BQoL.safe("ZCollision.getTarget", function()
            return zombie:getTarget() end)
        if ok3 and target then
            hasTarget = true
            targetIsPlayer = instanceof(target, "IsoPlayer")
        end
    end

    return ZombieCollision.passesScope(scope, hasTarget, targetIsPlayer)
end

-- ---------------------------------------------------------------- tick pass

local function onTick()
    if isClient() then
        if not warnedMPDisabled then
            warnedMPDisabled = true
            BQoL.warn("ZombieCollision disabled in multiplayer: avoiding setX/setY nudges on network-owned zombies")
        end
        return
    end

    -- Live master switch: the server can flip this mid-session in MP, and a
    -- sandbox change must not require a reload to take effect.
    if not BQoL.getBool("ZombieCollisionEnabled") then return end

    local player = getPlayer()
    if not player then return end

    local ok, list = BQoL.safe("ZCollision.zombieList", function()
        return getCell():getZombieList() end)
    if not ok or not list then return end

    local px, py = player:getX(), player:getY()
    local pz = player:getZ()

    local scanRadius = BQoL.getNumber("ZombieCollisionScanRadius")
    local scanSq = scanRadius * scanRadius
    local scope = BQoL.getNumber("ZombieCollisionScope")

    local near = {}
    for i = 0, list:size() - 1 do
        local zombie = list:get(i)
        local zx, zy = zombie:getX(), zombie:getY()
        local dx, dy = zx - px, zy - py
        local d2 = dx * dx + dy * dy

        if d2 <= scanSq and isCandidate(zombie, pz, scope) then
            near[#near + 1] = { d2 = d2, zombie = zombie, x = zx, y = zy }
        end
    end

    if #near < 2 then return end

    local chosen = ZombieCollision.selectNearest(near,
        BQoL.getNumber("ZombieCollisionMaxZombies"))
    if #chosen < 2 then return end

    local corrections = ZombieCollision.computeCorrections(chosen,
        BQoL.getNumber("ZombieCollisionPushRadius"),
        BQoL.getNumber("ZombieCollisionPushForce"))

    for i, entry in ipairs(chosen) do
        local push = corrections[i]
        if push.dx ~= 0 or push.dy ~= 0 then
            BQoL.safe("ZCollision.nudge", function()
                entry.zombie:setX(entry.x + push.dx)
                entry.zombie:setY(entry.y + push.dy)
            end)
        end
    end
end

BQoL.feature{
    id = "ZombieCollision",
    sandbox = "ZombieCollisionEnabled",
    init = function()
        Events.OnTick.Add(onTick)
    end,
}
