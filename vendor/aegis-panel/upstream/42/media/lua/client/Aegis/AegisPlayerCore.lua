-- Player panel foundation: shared client state, server sync, blue palette
require "Aegis/AegisTheme"

AegisPlayerClient = AegisPlayerClient or {}
-- nil until the server grants the panel, then
-- { role, color = {r,g,b} or nil, claimTiles, kits, boostReady, knoxVehicles }
AegisPlayerClient.state = nil

local MODULE = "AegisPlayer"
local RETRY_MS = 3000
local RETRY_MAX = 5

function AegisPlayerClient.enabled()
    return AegisPlayerClient.state ~= nil
end

-- blue palette for everything the player panel draws itself. Same keys as
-- Aegis.col with the gold family renamed to accent, so pages can swap the
-- table without touching the drawing helpers
AegisPlayerCol = {
    accent    = { r = 0.29, g = 0.56, b = 0.85 },
    accentHi  = { r = 0.42, g = 0.68, b = 0.94 },
    accentDim = { r = 0.17, g = 0.33, b = 0.51 },
}
for k, v in pairs(Aegis.col) do
    if k ~= "gold" and k ~= "goldHi" and k ~= "goldDim" then
        AegisPlayerCol[k] = v
    end
end

-- ---------- server sync ----------
-- the server answers ppReq with ppSync carrying the state table; a reply
-- without a role means the panel stays off for this player

local answered = false
local reqAt = nil
local reqTries = 0

local function normColor(t)
    if type(t) ~= "table" then return nil end
    local r, g, b = tonumber(t.r), tonumber(t.g), tonumber(t.b)
    if not r or not g or not b then return nil end
    -- engine role colors can arrive as 0..255
    if r > 1 or g > 1 or b > 1 then
        r, g, b = r / 255, g / 255, b / 255
    end
    return { r = r, g = g, b = b }
end

local function applySync(args)
    answered = true
    -- enabled carries the grant; the role is optional, every player on
    -- the server gets the base panel
    if type(args) ~= "table" or args.enabled ~= true then
        AegisPlayerClient.state = nil
        -- an explicit false means the server has the player area switched
        -- off in its sandbox settings, asking again every minute would be
        -- pointless traffic for the whole session
        if type(args) == "table" and args.enabled == false then
            AegisPlayerClient.refused = true
        end
        return
    end
    AegisPlayerClient.refused = false
    AegisPlayerClient.state = {
        role = type(args.role) == "string" and args.role ~= "" and args.role or nil,
        color = normColor(args.color),
        claimTiles = tonumber(args.claimTiles) or 0,
        kits = args.kits == true,
        -- a configured boost key opens the kits page even without the
        -- kits flag, the server sends the boost slice then
        boostReady = args.boostReady == true,
        -- Knox Claim owns the vehicles on this server, the vehicles page
        -- pulls its remember button then. This table is rebuilt field by
        -- field, so anything new on the server side has to be listed here
        -- as well or it is silently dropped on arrival
        knoxVehicles = args.knoxVehicles == true,
    }
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= MODULE then return end
    if command == "ppSync" then
        applySync(args)
    elseif command == "sosNotice" and args and args.key then
        -- distress call for admins: the server picked the recipients,
        -- this side renders. A toast was far too easy to miss (it lives
        -- in a panel header that is usually closed), so the call gets
        -- its own alert card with a jump button
        -- guarded call: the alert file loads later alphabetically, and a
        -- packet during that window must not kill the listener
        if AegisSosAlert and AegisSosAlert.push then
            pcall(AegisSosAlert.push, args)
        else
            local text = args.par and getText(args.key, tostring(args.par)) or getText(args.key)
            Aegis.showToast(text)
        end
    end
end)

local function sendReq()
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, MODULE, "ppReq", {})
    reqAt = getTimestampMs()
end

Events.OnGameStart.Add(function()
    AegisPlayerClient.state = nil
    answered = false
    reqAt = nil
    reqTries = 0
    if not isClient() then
        -- solo has no server round trip, the panel is always available
        AegisPlayerClient.state = { role = "Solo", claimTiles = 0, kits = true }
        return
    end
    sendReq()
end)

-- the first ppReq can race the connection, repeat a few times until a
-- reply arrives (same idea as the rights retry of the admin window).
-- After that, as long as no grant exists, ask again once a minute: an
-- admin may assign the role mid session and the server push can only
-- reach clients it knows are online (belt on top of the push)
local POLL_MS = 60000

Events.OnTick.Add(function()
    if reqAt == nil then return end
    local now = getTimestampMs()
    if not answered then
        if reqTries >= RETRY_MAX then return end
        if now - reqAt < RETRY_MS then return end
        reqTries = reqTries + 1
        sendReq()
        return
    end
    if AegisPlayerClient.state == nil and isClient()
        and not AegisPlayerClient.refused
        and now - reqAt >= POLL_MS then
        sendReq()
    end
end)
