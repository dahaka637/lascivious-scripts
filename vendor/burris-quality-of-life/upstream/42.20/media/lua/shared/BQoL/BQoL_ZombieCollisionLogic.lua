--[[
    Burris Quality of Life -- zombie collision decision logic.

    Pure functions over plain values, so tools/test/zombie_collision.lua can
    exercise the rules without a running game. The client module
    (BQoL_ZombieCollision.lua) reads the game state and applies the results.

    The model is a soft personal-space push: two zombies closer than
    pushRadius are nudged apart along their separation vector, scaled by how
    deep the overlap is. Forces are deliberately tiny -- per-tick nudges that
    accumulate into visible de-clumping over a second or two, rather than an
    instant shove that would read as zombies sliding on ice.
]]

require "BQoL/BQoL_Core"

BQoL = BQoL or {}
BQoL.ZombieCollision = BQoL.ZombieCollision or {}

local ZombieCollision = BQoL.ZombieCollision

-- ------------------------------------------------------------ scope filter

--[[
    Which zombies take part, per the sandbox scope enum:
      1 = chasing  -- only zombies whose current target is a player
      2 = aggressive -- any zombie with a target
      3 = all      -- every nearby zombie

    `hasTarget` and `targetIsPlayer` are resolved by the caller, which owns
    the game objects; this function only owns the rule. Unknown enum values
    fall back to "chasing", the behaviour the feature exists for.
]]
function ZombieCollision.passesScope(scope, hasTarget, targetIsPlayer)
    scope = tonumber(scope) or 1

    if scope == 3 then return true end
    if scope == 2 then return hasTarget == true end
    return hasTarget == true and targetIsPlayer == true
end

-- --------------------------------------------------------- nearest select

--[[
    Keeps only the `maxCount` entries with the smallest squared distance.

    `entries` is an array of tables that carry a `d2` field; the entries are
    otherwise opaque and pass through unchanged. The cap is what makes the
    performance cost flat: whether the cell holds 10 zombies or 100, the
    pairwise pass below never sees more than maxCount of them. Input order is
    not modified; the result is a fresh array sorted by distance.
]]
function ZombieCollision.selectNearest(entries, maxCount)
    local sorted = {}
    for _, entry in ipairs(entries) do
        sorted[#sorted + 1] = entry
    end

    table.sort(sorted, function(a, b) return a.d2 < b.d2 end)

    local out = {}
    local limit = math.min(tonumber(maxCount) or 0, #sorted)
    for i = 1, limit do
        out[i] = sorted[i]
    end
    return out
end

-- ----------------------------------------------------------- push physics

--[[
    Computes per-zombie position corrections for one tick.

    `positions` is an array of { x, y } in tile coordinates. The result is a
    parallel array of { dx, dy } to add to each position. Each pair closer
    than pushRadius splits a push scaled by overlap depth, so deeply
    overlapped zombies separate faster than ones just brushing.

    Two zombies at the exact same spot have no separation direction; they get
    a deterministic shove along +x/-x. Any direction is fine -- the next tick
    they have a real vector -- but a random one would make tests (and bug
    reports) non-reproducible.
]]
function ZombieCollision.computeCorrections(positions, pushRadius, pushForce)
    local out = {}
    for i = 1, #positions do
        out[i] = { dx = 0, dy = 0 }
    end

    pushRadius = tonumber(pushRadius) or 0
    pushForce = tonumber(pushForce) or 0
    if pushRadius <= 0 or pushForce <= 0 then return out end

    local radiusSq = pushRadius * pushRadius

    for i = 1, #positions - 1 do
        for j = i + 1, #positions do
            local dx = positions[i].x - positions[j].x
            local dy = positions[i].y - positions[j].y
            local distSq = dx * dx + dy * dy

            if distSq < radiusSq then
                local ux, uy, mag

                if distSq > 0 then
                    local dist = math.sqrt(distSq)
                    ux, uy = dx / dist, dy / dist
                    mag = pushForce * (1 - dist / pushRadius) * 0.5
                else
                    ux, uy = 1, 0
                    mag = pushForce * 0.5
                end

                out[i].dx = out[i].dx + ux * mag
                out[i].dy = out[i].dy + uy * mag
                out[j].dx = out[j].dx - ux * mag
                out[j].dy = out[j].dy - uy * mag
            end
        end
    end

    return out
end
