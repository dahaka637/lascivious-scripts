-- Local-player zombie-proximity check for LasciviousShop_Window.lua's
-- danger-dimming effect. Client-only and local by design: each player only
-- ever sees their own danger, nothing here syncs to the server or affects
-- the purchase flow, it's purely a rendering decision.
--
-- Same technique as HardcoreKitsDanger.zombiesNear (HardcoreKits_Danger.lua)
-- and LFS_Server.lua's SafeZone check: cell:getZombieList() + squared
-- distance (no sqrt) + z:isDead() to skip corpses.
require "LasciviousShop_Shared"

LasciviousShopDanger = LasciviousShopDanger or {}

-- true if at least one live zombie is within radiusTiles of the player.
-- Wrapped in pcall -- this runs every frame while the shop window is open
-- (throttled, see updateDangerAlpha in Window.lua), so a failure here must
-- never be able to break the window.
function LasciviousShopDanger.zombiesNear(player, radiusTiles)
    if not player or not radiusTiles or radiusTiles <= 0 then return false end
    local ok, found = pcall(function()
        local cell = getCell()
        if not cell or not cell.getZombieList then return false end
        local zlist = cell:getZombieList()
        if not zlist then return false end
        local px, py = player:getX(), player:getY()
        local radiusSq = radiusTiles * radiusTiles
        for i = 0, zlist:size() - 1 do
            local z = zlist:get(i)
            if z and not z:isDead() then
                local dx, dy = z:getX() - px, z:getY() - py
                if (dx * dx + dy * dy) <= radiusSq then return true end
            end
        end
        return false
    end)
    return ok and found or false
end
