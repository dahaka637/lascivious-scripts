-- ============================================================================
-- MapAllKnownFix
--
-- 修复 Build 42.20.3 联机（MP）客户端 MapAllKnown（沙盒选项"显示全地图"）
-- 不生效的官方 bug：
--
--   42.20.2: PlayerVisitedPacket.processClient 在收到服务器下发的已探索数据后
--            会检查 SandboxOptions.Map.MapAllKnown，若为 true 则对全图调用
--            WorldMapVisited.setKnownInCells()。
--   42.20.3: PlayerVisitedPacket 被删除，改走 RequestDataPacket(RequestID.
--            PlayerVisited) -> WorldMapVisited.receiveRequestData()，新路径
--            只用服务器数据覆盖本地 visited 数组，完全漏掉了 MapAllKnown 的
--            处理，导致联机客户端始终有迷雾。
--
-- 本 mod 在进图后补做 setKnownInCells()，恢复官方预期行为。
-- 仅联机客户端生效（单机该选项工作正常，不做多余操作）；不影响服务器数据，
-- 可随时装卸。
-- ============================================================================

if isServer() and not isClient() then
    -- 双保险：本文件只应被客户端加载
    return
end

local TICKS_PER_APPLY = 60 -- 约 1 秒重试一次
local MAX_APPLIES = 10     -- 进图/重生后最多重试 10 次，确保在收到服务器
                           -- PlayerVisited 数据之后执行（该数据会覆盖本地标记）

local function isMapAllKnownEnabled()
    if not isClient() then
        return false -- 单机无此 bug
    end
    local option = getSandboxOptions():getOptionByName("Map.MapAllKnown")
    return option ~= nil and option:getValue() == true
end

local function applyMapAllKnown()
    if not isMapAllKnownEnabled() then
        return
    end
    local world = getWorld()
    if not world then
        return
    end
    local metaGrid = world:getMetaGrid()
    if not metaGrid then
        return
    end
    local minX, minY = metaGrid:getMinX(), metaGrid:getMinY()
    local maxX, maxY = metaGrid:getMaxX(), metaGrid:getMaxY()
    if minX > maxX or minY > maxY then
        return
    end
    WorldMapVisited.getInstance():setKnownInCells(minX, minY, maxX, maxY)
end

local ticks = 0
local appliesLeft = 0

local function onTick()
    ticks = ticks + 1
    if ticks < TICKS_PER_APPLY then
        return
    end
    ticks = 0
    applyMapAllKnown()
    appliesLeft = appliesLeft - 1
    if appliesLeft <= 0 then
        Events.OnTick.Remove(onTick)
    end
end

local function scheduleApplies()
    appliesLeft = MAX_APPLIES
    ticks = TICKS_PER_APPLY -- 下一 tick 立即先执行一次
    Events.OnTick.Remove(onTick) -- 防重复注册
    Events.OnTick.Add(onTick)
end

Events.OnGameStart.Add(scheduleApplies)
Events.OnCreatePlayer.Add(function(playerIndex, player)
    scheduleApplies()
end)
