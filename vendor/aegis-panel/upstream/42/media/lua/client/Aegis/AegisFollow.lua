-- Spectator follow: glues the admin to a target player, range independent.
-- Lua has no detached camera, so the ghost admin himself glides after the
-- target using the same field writes teleportTo does internally.
require "Aegis/AegisTheme"
require "Aegis/AegisWindow"
require "Aegis/AegisPagePowers"

AegisFollow = AegisFollow or {}

-- active follow: target username, last poll time, last two server samples
local state = nil
local hud = nil

-- the server grants at most one answer per started second, asking faster
-- would only burn bandwidth (see Aegis_Follow.lua)
local POLL_MS = 1000
-- remote player objects keep their last synced coords outside streaming
-- range; their live position only counts while it agrees with the server
local TRUST_DIST = 20
-- beyond this a glide would stream every chunk along the way, jump instead
local GLIDE_MAX = 40
-- trailing distance the glide settles on; the aim point slides in with it
-- so the step size fades to zero instead of switching off at a threshold
local GAP = 2.0
local GLIDE_RATE = 0.12
-- ceiling for one frame step in tiles per 33.3 ms, roughly 36 tiles/s:
-- above any sprint, below a teleport, keeps a source switch from landing
-- as a single visible jump
local MAX_STEP = 1.2
-- server samples are up to a second old; carrying the last known velocity
-- forward turns the sample stairs into a continuously moving aim point
local DR_MAX_AGE = 1500
local DR_MAX_GAP = 3000
local DR_MAX_SPEED = 40

-- ------------------------------------------------------------------
-- small HUD pill at the top edge, click ends the follow
-- ------------------------------------------------------------------

local FollowHud = ISPanel:derive("AegisFollowHud")

function FollowHud:prerender()
    local c = Aegis.col
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 14, 0.92, c.line, c.dark)
    Aegis.icon(self, "ghost", 10, math.floor((self.height - 16) / 2), 16, 1, c.gold)
    Aegis.text(self, self.label, 34, math.floor((self.height - Aegis.fontH(UIFont.Small)) / 2), UIFont.Small, c.goldHi)
    Aegis.updateTooltip(self)
end

function FollowHud:onMouseDown(x, y)
    AegisFollow.stop()
    return true
end

local function hudHide()
    if hud then
        hud:removeFromUIManager()
        hud = nil
    end
end

local function hudShow(username)
    hudHide()
    local label = getText("UI_Aegis_Follow") .. ": " .. tostring(username)
    local w = Aegis.strW(UIFont.Small, label) + 46
    local o = ISPanel:new(math.floor((getCore():getScreenWidth() - w) / 2), 16, w, 28)
    setmetatable(o, FollowHud)
    FollowHud.__index = FollowHud
    o.background = false
    o.label = label
    o.tooltip = getText("UI_Aegis_FollowStop")
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    hud = o
end

-- ------------------------------------------------------------------
-- ghost combo (god, invisible, noclip, fastmove)
-- ------------------------------------------------------------------

local function ghostOn(p)
    return p:isGodMod() and p:isInvisible() and p:isNoClip() and ISFastTeleportMove.cheat == true
end

-- route through the powers page when it exists so its toggles stay in
-- sync; pages build lazily, so the same cheats are set directly otherwise
-- (mirror of GHOST_POWERS in AegisPagePowers.lua)
local function ensureGhost(p)
    if ghostOn(p) then return end
    local panel = AegisWindow.instance and AegisWindow.instance.page
        and AegisWindow.instance:page("powers")
    if panel and AegisPagePowers and AegisPagePowers.onGhost then
        AegisPagePowers.onGhost(panel, true)
        return
    end
    Aegis.ensureSoloRole()
    p:setGodMod(true)
    p:setInvisible(true)
    p:setNoClip(true)
    ISFastTeleportMove.cheat = true
    p:setFastMoveCheat(true)
    Aegis.syncPowers(p)
    Aegis.logAction("powers", "Ghost mode enabled")
end

-- ------------------------------------------------------------------
-- public API
-- ------------------------------------------------------------------

function AegisFollow.isOn()
    return state ~= nil
end

function AegisFollow.current()
    return state and state.username or nil
end

function AegisFollow.start(username)
    if not username or username == "" then return end
    if state and state.username == username then
        AegisFollow.stop()
        return
    end
    local p = getPlayer()
    if not p or p:isDead() then return end
    if p:getUsername() == username then return end
    if state then AegisFollow.stop(true) end
    ensureGhost(p)
    state = { username = username, lastReq = 0, serverPos = nil, serverPrev = nil }
    hudShow(username)
    Aegis.showToast(getText("UI_Aegis_Follow") .. ": " .. tostring(username))
    Aegis.logAction("players", "Follow started: " .. username)
end

-- silent: target switch and the gone reply bring their own feedback
function AegisFollow.stop(silent)
    if not state then return end
    local name = state.username
    state = nil
    hudHide()
    Aegis.logAction("players", "Follow stopped: " .. name)
    if not silent then
        Aegis.showToast(getText("UI_Aegis_FollowStop"))
    end
end

-- panel teleports end the follow, the tick would drag the admin right back
local baseTeleport = Aegis.teleportSmart
Aegis.teleportSmart = function(x, y, z, username)
    if state then AegisFollow.stop() end
    return baseTeleport(x, y, z, username)
end

-- ------------------------------------------------------------------
-- follow tick
-- ------------------------------------------------------------------

-- same field pattern teleportTo(III) uses internally (bytecode verified),
-- kept as floats so the glide stays fractional
local function setPlane(p, x, y)
    p:setX(x)
    p:setY(y)
    p:setLastX(x)
    p:setLastY(y)
end

-- server position moved on by the velocity of the last two samples, so the
-- aim point keeps moving between the once per second replies
local function serverAim(now)
    local cur = state.serverPos
    if not cur then return nil end
    local prev = state.serverPrev
    if not prev then return cur.x, cur.y, cur.z end
    local dt = cur.t - prev.t
    if dt <= 0 or dt > DR_MAX_GAP then return cur.x, cur.y, cur.z end
    local vx, vy = (cur.x - prev.x) / dt, (cur.y - prev.y) / dt
    -- a teleport between two samples is not a velocity
    if math.sqrt(vx * vx + vy * vy) * 1000 > DR_MAX_SPEED then return cur.x, cur.y, cur.z end
    local age = now - cur.t
    if age < 0 then age = 0 end
    if age > DR_MAX_AGE then age = DR_MAX_AGE end
    return cur.x + vx * age, cur.y + vy * age, cur.z
end

Events.OnTick.Add(function()
    if not state then return end
    local p = getPlayer()
    if not p or p:isDead() then
        AegisFollow.stop()
        return
    end

    -- teleports that bypass Aegis.teleportSmart (faction page, world map,
    -- chat command) move the admin without notice; a jump this loop did
    -- not write itself ends the follow instead of dragging him back
    local px, py, pz = p:getX(), p:getY(), p:getZ()
    local last = state.lastSelf
    if last and math.max(math.abs(px - last.x), math.abs(py - last.y)) > 10 then
        AegisFollow.stop()
        return
    end
    state.lastSelf = { x = px, y = py }

    -- the server position is the source of truth, remote objects go stale
    -- outside streaming range (movement sync only runs in range)
    local now = getTimestampMs()
    if isClient() then
        if now - state.lastReq >= POLL_MS then
            state.lastReq = now
            sendClientCommand(p, AegisShared.MODULE, "followPos", { username = state.username })
        end
    end

    -- fresh lookup every tick, never cached (object identity unreliable);
    -- guarded, the global is GameClient backed and solo has no client
    local ox, oy, oz
    pcall(function()
        local obj = getPlayerFromUsername(state.username)
        if obj then ox, oy, oz = obj:getX(), obj:getY(), obj:getZ() end
    end)

    local spx, spy, spz = serverAim(now)
    local tx, ty, tz
    if ox and spx then
        -- live object wins only while it agrees with the server position,
        -- that means it is inside synced range and smooth per tick; the
        -- comparison runs against the moved on sample, a driving target
        -- would otherwise fail it purely because the sample is a second old
        local d = math.max(math.abs(ox - spx), math.abs(oy - spy))
        if d <= TRUST_DIST then
            tx, ty, tz = ox, oy, oz
        else
            tx, ty, tz = spx, spy, spz
        end
    elseif spx then
        tx, ty, tz = spx, spy, spz
    elseif ox then
        tx, ty, tz = ox, oy, oz
    end
    if not tx then return end

    -- a seated admin would fight the vehicle for the position
    local seated = p:getVehicle() ~= nil
    if seated then return end

    local dx, dy = tx - px, ty - py
    local dist = math.sqrt(dx * dx + dy * dy)
    -- clamped, not floored: on stairs the target height runs fractional and
    -- rounding it would drop or lift the camera by a whole storey per frame
    tz = math.max(-32, math.min(31, tonumber(tz) or 0))

    -- aim GAP tiles short of the target instead of stopping inside a dead
    -- zone: the aim point runs into our own position as dist approaches GAP
    if dist > GLIDE_MAX then
        -- canonical self teleport for the long hop (anti snapback built in)
        local k = (dist - GAP) / dist
        local jx, jy = px + dx * k, py + dy * k
        p:teleportTo(jx, jy, math.floor(tz) + 0.0)
        state.lastSelf = { x = jx, y = jy }
    elseif dist > GAP then
        -- dist > GAP > 0 here, the division cannot see a zero
        local k = (dist - GAP) / dist
        local nx = Aegis.glide(px, px + dx * k, GLIDE_RATE)
        local ny = Aegis.glide(py, py + dy * k, GLIDE_RATE)
        local sx, sy = nx - px, ny - py
        local step = math.sqrt(sx * sx + sy * sy)
        local cap = MAX_STEP * Aegis.delta()
        if step > cap then
            local f = cap / step
            nx, ny = px + sx * f, py + sy * f
        end
        setPlane(p, nx, ny)
        state.lastSelf = { x = nx, y = ny }
    end
    -- hold the target height every tick, the engine pulls airborne
    -- characters back towards the ground (ISFastTeleportMove pattern);
    -- comparing values instead of floors also catches a leftover fraction
    -- at ground level, where the floor compare wrote nothing at all
    if tz ~= 0 or math.abs(pz - tz) > 0.001 then
        p:setZ(tz + 0.0)
        p:setLastZ(tz + 0.0)
    end
end)

-- ------------------------------------------------------------------
-- server replies
-- ------------------------------------------------------------------

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE then return end
    -- rights lost mid follow: the server denies the players area, keeping
    -- the loop alive would toast the generic denied every poll forever
    if command == "denied" and state and args and args.area == "players" then
        AegisFollow.stop()
        return
    end
    if command ~= "followPos" then return end
    if not state or not args or args.username ~= state.username then return end
    if args.gone then
        Aegis.showToast(getText("UI_Aegis_FollowGone"))
        AegisFollow.stop(true)
        return
    end
    local x, y = tonumber(args.x), tonumber(args.y)
    if not x or not y then return end
    state.serverPrev = state.serverPos
    state.serverPos = { x = x, y = y, z = tonumber(args.z) or 0, t = getTimestampMs() }
end)

-- fresh session starts unfollowed
Events.OnGameStart.Add(function()
    state = nil
    hudHide()
end)
