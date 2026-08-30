-- Head tag above the player: the red "admin" text is the name of the
-- engine role in the role color. Instead of overwriting it we create our
-- own engine role with the desired name and color and assign it; the
-- engine distributes name and color to all clients itself and stores them
-- in the server DB. No permissions are lost, the new role takes over all
-- capabilities of the target player's previous role.
require "Aegis/AegisTheme"

AegisRoleTag = AegisRoleTag or {}

-- fixed color choices for the chips, values 0..1
AegisRoleTag.COLORS = {
    { key = "UI_Aegis_ColorGold",    color = { r = 0.843, g = 0.647, b = 0.290 } },
    { key = "UI_Aegis_ColorRed",     color = { r = 0.804, g = 0.320, b = 0.278 } },
    { key = "UI_Aegis_ColorBlue",    color = { r = 0.360, g = 0.560, b = 0.900 } },
    { key = "UI_Aegis_ColorGreen",   color = { r = 0.420, g = 0.690, b = 0.440 } },
    { key = "UI_Aegis_ColorPurple", color = { r = 0.660, g = 0.450, b = 0.850 } },
    { key = "UI_Aegis_ColorWhite",   color = { r = 1.000, g = 1.000, b = 1.000 } },
}

function AegisRoleTag.colorChips()
    local chips = {}
    for _, f in ipairs(AegisRoleTag.COLORS) do
        table.insert(chips, { label = getText(f.key), value = f.color })
    end
    return chips
end

-- creation in progress, no second one may start meanwhile
local run = nil

-- networkUserAction is a fire-and-forget network packet without a return
-- channel; whether the server really accepted the assignment only shows in
-- the synced getRole of the target (the same ExtraInfo broadcast that
-- also delivers the visible head tag)
local pendingConfirm = nil

-- tracked tag removals (SetRole back to a plain role), one per username;
-- the tag role is only janitor deleted AFTER the flip is confirmed,
-- deleting earlier races the server queue
local pendingResets = {}

-- post confirm lift of a self worn tag role, pure Roles edit
local lift = nil

-- SetRole returns NO value to the client on the server side
-- (bytecode-verified: NetworkUserActionPacket.processServer unconditionally
-- pops the return value of GameServer.changeRole) and can end in an
-- uncaught NullPointerException when the role is not yet registered server
-- side. A single packet that hits this window silently never arrives.
-- SetRole is therefore resent at intervals as long as the role is in the
-- server-confirmed catalog (engineRole ~= nil). This is safe, SetRole is
-- idempotent and never escalates permissions.
-- Budget: the server serializes SetRole behind every queued Roles.save
-- (each moveRole triggers a full save) and processed accepted packets
-- 25 to 60 seconds AFTER sending in the. The old
-- 4x1500ms budget declared such accepts as failures, so the window now
-- spans roughly two minutes with gentle resends.
local SETROLE_ATTEMPTS = 24
local SETROLE_INTERVAL = 5000

local function toast(key, a, b)
    Aegis.showToast(getText(key, a, b))
end

local function players(username)
    if isClient() then
        local ok, p = pcall(getPlayerFromUsername, username)
        if ok then return p end
        return nil
    end
    -- solo has exactly one player
    return getPlayer()
end

local function engineRole(name)
    local found = nil
    pcall(function()
        local roles = getRoles()
        for i = 0, roles:size() - 1 do
            local r = roles:get(i)
            if r and r:getName() == name then
                found = r
                break
            end
        end
    end)
    return found
end

-- marker in the role description: the head tag only cleans up roles
-- carrying this marker later
local MARKER = "Aegis Kopf-Tag"

-- true if the name currently belongs to a DIFFERENT online player than
-- targetUsername; prevents two admins with the same desired name from
-- pulling the role (including capability reassignment) out from under
-- each other
local function nameCollides(name, targetUsername)
    local found = false
    pcall(function()
        local players = getOnlinePlayers()
        if not players then return end
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p and p:getUsername() ~= targetUsername then
                local r = p:getRole()
                if r and r:getName() == name then
                    found = true
                    break
                end
            end
        end
    end)
    return found
end

-- name collision with a read-only engine role (admin, user, ...), those
-- can neither be recolored nor given capabilities
local function isProtectedName(name)
    local lowered = string.lower(name)
    local found = false
    local roles = getRoles()
    for i = 0, roles:size() - 1 do
        local r = roles:get(i)
        if r and r:isReadOnly() and string.lower(r:getName()) == lowered then
            found = true
            break
        end
    end
    return found
end

-- current engine role of a player, as far as readable client side
-- (the ExtraInfo sync keeps the role fresh on every streamed IsoPlayer)
function AegisRoleTag.currentRole(username)
    local p = players(username)
    if not p then return nil end
    local name = nil
    local role = p:getRole()
    if role then name = role:getName() end
    return name
end

-- capability table for setupRole: everything the previous role could do
-- plus tag rendering, so nobody loses permissions
local function copyCaps(base)
    local caps = {}
    local all = getCapabilities()
    for i = 0, all:size() - 1 do
        local cap = all:get(i)
        caps[cap] = base ~= nil and base:hasCapability(cap) == true
    end
    caps[Capability.ToggleWriteRoleNameAbove] = true
    return caps
end

local function cleanName(name)
    name = tostring(name or "")
    name = name:gsub("[%c|]", "")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if #name > 24 then
        local cut = 24
        -- avoid cutting inside a UTF-8 sequence (umlauts)
        while cut > 0 do
            local b = string.byte(name, cut + 1)
            if b and b >= 128 and b < 192 then cut = cut - 1 else break end
        end
        name = name:sub(1, cut)
    end
    return name
end

-- highest read-only position strictly below pos, nil when none exists
local function anchorBelow(pos)
    local best = nil
    local roles = getRoles()
    for i = 0, roles:size() - 1 do
        local r = roles:get(i)
        if r and r:isReadOnly() then
            local p = r:getPosition()
            if p < pos and (best == nil or p > best) then best = p end
        end
    end
    return best
end

-- highest position reachable via moveRole that is GUARANTEED below the
-- requester on the SERVER, no matter how the server orders the roles
-- inside a band. Gate 2 of GameServer.changeRole (bytecode-verified)
-- rejects any assignment where the new role ranks above the requester,
-- and the client role mirror cannot see the server's order WITHIN a band
-- (mirror showed the new role one rung below the
-- own role, the server had it above and silently denied 16 packets).
-- Read-only roles have FIXED positions (Roles.updatePositions), so the
-- only positions the client can fully trust are "read-only anchor + 1":
--  * own role read-only (admin=7000 etc): the band directly below is
--    already provably under the requester, e.g. 6001
--  * own role NOT read-only (own band shared with other tag roles): drop
--    one FULL band, e.g. own role somewhere in the 3000s parks at 2001
-- returns nil when no safe anchor exists (own rank in the lowest band);
-- that case MUST be refused up front, the server would always deny
local function safeCeiling(ownPos, ownReadOnly)
    local a = anchorBelow(ownPos)
    if a ~= nil and not ownReadOnly then
        a = anchorBelow(a)
    end
    if a == nil then return nil end
    return a + 1
end

-- solo: Roles.init never runs, so build the role locally and set it
-- directly, same pattern as Aegis.ensureSoloRole
local function assignSolo(name, color)
    local ok = pcall(function()
        local p = getPlayer()
        local base = p:getRole()
        local role = Role.new(name)
        local all = getCapabilities()
        for i = 0, all:size() - 1 do
            local cap = all:get(i)
            if base == nil or base:hasCapability(cap) then
                role:addCapability(cap)
            end
        end
        role:addCapability(Capability.ToggleWriteRoleNameAbove)
        role:setColor(Color.new(color.r, color.g, color.b, 1.0))
        p:setRole(role)
        p:setShowAdminTag(true)
    end)
    return ok
end

-- core flow: ensure an engine role with the desired name exists, set color
-- and capabilities, then assign it to the player via networkUserAction.
-- A freshly created role only appears client side with the server's
-- catalog broadcast, so the tick handler waits for it.
function AegisRoleTag.createAndAssign(username, name, color)
    if not Aegis.canSee("roles") then return end
    name = cleanName(name)
    if name == "" then
        toast("UI_Aegis_HeadTagErrorName")
        return
    end
    if type(color) ~= "table" or not color.r then
        color = AegisRoleTag.COLORS[1].color
    end

    if not isClient() then
        if assignSolo(name, color) then
            toast("UI_Aegis_HeadTagDone", name)
            Aegis.logAction("roles", string.format("Head tag \"%s\" set (solo)", name))
        else
            toast("UI_Aegis_HeadTagError")
        end
        return
    end

    if run then
        toast("UI_Aegis_HeadTagInProgress")
        return
    end
    -- a confirm still in flight for the SAME player is superseded by the
    -- new wish; one for another player keeps its single tracking slot
    if pendingConfirm then
        if pendingConfirm.username == username then
            print("[Aegis] tag: dropping stale confirm for " .. tostring(username) .. " (superseded by new run)")
            pendingConfirm = nil
        else
            toast("UI_Aegis_HeadTagInProgress")
            return
        end
    end
    for i = #pendingResets, 1, -1 do
        if pendingResets[i].username == username then
            print("[Aegis] tag: dropping pending reset for " .. tostring(username) .. " (superseded by new run)")
            table.remove(pendingResets, i)
        end
    end
    if lift then
        print("[Aegis] tag: cancelling lift of \"" .. tostring(lift.name) .. "\" (new run touches the role order)")
        lift = nil
    end

    local me = getPlayer()
    local myRole = me and me:getRole()
    local allowed = myRole ~= nil and myRole:hasCapability(Capability.ChangeAccessLevel) == true
    if not allowed then
        toast("UI_Aegis_HeadTagErrorPermission")
        return
    end

    local target = players(username)
    if not target then
        print("[Aegis] tag: abort, target player object not resolvable for " .. tostring(username) .. " (offline or not streamed)")
        toast("UI_Aegis_HeadTagErrorOffline")
        return
    end
    print("[Aegis] tag: starting for " .. tostring(username) .. ", name \"" .. name .. "\"")

    -- position hierarchy like the vanilla user list: only someone above the
    -- target may change its role, otherwise the server rejects it
    local rankOk = true
    local targetRole = target:getRole()
    if targetRole and myRole and myRole:getPosition() < targetRole:getPosition() then rankOk = false end
    if not rankOk then
        toast("UI_Aegis_HeadTagErrorRank")
        return
    end

    if isProtectedName(name) then
        toast("UI_Aegis_HeadTagErrorProtected")
        return
    end

    -- a freshly created name must not clash with a foreign, already taken
    -- role (setupRole would overwrite color/permissions of another player);
    -- only the target's own previous role may carry the same name
    -- (recoloring/refitting is allowed)
    if name ~= AegisRoleTag.currentRole(username) and nameCollides(name, username) then
        toast("UI_Aegis_HeadTagErrorTaken")
        return
    end

    local caps = nil
    local ok = pcall(function() caps = copyCaps(target:getRole()) end)
    if not ok or caps == nil then
        toast("UI_Aegis_HeadTagError")
        return
    end

    -- record own and target position up front: after creation the new role
    -- must actively be sorted between these two values, otherwise it slips
    -- below "banned" and in the worst case locks the admin himself out of
    -- every further rank check
    local ownPosition, targetPosition = 0, 0
    ownPosition = myRole:getPosition()
    targetRole = target:getRole()
    if targetRole then targetPosition = targetRole:getPosition() end

    local isSelf = target:getUsername() == me:getUsername()
    local ownReadOnly = myRole:isReadOnly() == true

    -- pre-flight for the guaranteed rejection: without a read-only anchor
    -- to park the new role under, gate 2 of the server MUST deny (live
    -- the demote cycles had pressed the own rank into the 1000s
    -- and every further attempt was doomed). Refuse honestly instead of
    -- burning silent attempts; this state needs the documented DB repair
    local ceiling = safeCeiling(ownPosition, ownReadOnly)
    if ceiling == nil then
        print("[Aegis] tag: abort, no safe anchor below own position " .. tostring(ownPosition) .. " (rank in the lowest band, needs a DB repair)")
        toast("UI_Aegis_HeadTagErrorLowBand")
        return
    end
    print("[Aegis] tag: ownPos=" .. tostring(ownPosition) .. " readOnly=" .. tostring(ownReadOnly) .. " self=" .. tostring(isSelf) .. " safeCeiling=" .. tostring(ceiling))

    -- forensic blind spot, kept visible: when the target's role shares
    -- the own (non read-only) band, gate 1 compares a server order the
    -- client mirror cannot verify, so a silent denial is still possible
    if not isSelf and not ownReadOnly then
        targetRole = target:getRole()
        if targetRole and not targetRole:isReadOnly() and targetRole:getName() ~= myRole:getName() then
            local bandAnchor = anchorBelow(ownPosition)
            local tp = targetRole:getPosition()
            if bandAnchor and tp > bandAnchor then
                print("[Aegis] tag: warning, target role \"" .. tostring(targetRole:getName()) .. "\"@" .. tostring(tp) .. " shares the own band (own " .. tostring(ownPosition) .. "), server order inside a band is invisible to the client, gate 1 may still deny")
            end
        end
    end

    -- refit of a role the target ALREADY wears: no SetRole and no position
    -- dance needed, an in-place setupRole updates color and capabilities.
    -- Running the full flow here ping-ponged the positioner against the
    -- actor's own live rank when the role was his own
    if name == AegisRoleTag.currentRole(username) then
        local okRefit = pcall(function()
            local r = engineRole(name)
            setupRole(r, MARKER, Color.new(color.r, color.g, color.b, 1.0), caps)
        end)
        if okRefit then
            toast("UI_Aegis_HeadTagDone", name)
            Aegis.logAction("roles", string.format("Head tag \"%s\" refitted", name))
        else
            toast("UI_Aegis_HeadTagError")
        end
        return
    end

    -- remember the target's previous, possibly self-created role: after a
    -- successful rename we clean it up, otherwise the 255-slot role catalog
    -- fills with corpses on every rename
    local previousRole = AegisRoleTag.currentRole(username)

    run = {
        username = username,
        name = name,
        color = color,
        caps = caps,
        target = target,
        myRole = myRole,
        ownPosition = ownPosition,
        ownReadOnly = ownReadOnly,
        targetPosition = targetPosition,
        isSelf = isSelf,
        -- self assignments park one full band lower; after confirmation
        -- the now worn role gets lifted back to the top of the band under
        -- the old own band, otherwise repeated self changes ratchet the
        -- own rank down band by band
        liftTarget = (isSelf and not ownReadOnly) and ((anchorBelow(ownPosition) or 0) + 1) or nil,
        previousRole = (previousRole ~= name) and previousRole or nil,
        pushAttempts = 0,
        step = "role",
        -- generous budget: every push serializes behind a full server side
        -- Roles.save and the position broadcast arrived up to a minute
        -- late in the
        deadline = getTimestampMs() + 120000,
        nextAt = 0,
    }

    if engineRole(name) == nil then
        local ok2 = pcall(function() addRole(name) end)
        if not ok2 then
            run = nil
            toast("UI_Aegis_HeadTagError")
        end
    end
end

-- removes an orphaned self-created role (only with our description marker,
-- safety net against foreign roles). Deletion is rank-gated like every
-- role change: after a switch the old role sits ABOVE the requester and a
-- plain deleteRole is silently denied: "Owner" and
-- "Test" survived their cleanup). The janitor therefore verifies by
-- outcome and alternates delete attempts with one-rung push-downs until
-- the role is gone or the budget is spent
local janitor = {}

-- a role an online player still wears must never be janitor deleted:
-- the engine's deleteRole resets every wearer to plain user and skips
-- both rank gates while doing it
local function wornOnline(name)
    local worn = false
    pcall(function()
        local list = getOnlinePlayers()
        if not list then return end
        for i = 0, list:size() - 1 do
            local pl = list:get(i)
            if pl then
                local r = pl:getRole()
                if r and r:getName() == name then
                    worn = true
                    return
                end
            end
        end
    end)
    return worn
end

local function cleanupRole(name)
    if not name then return end
    local r = engineRole(name)
    if r == nil then return end
    local marked = not r:isReadOnly() and r:getDescription() == MARKER
    if not marked then return end
    for _, j in ipairs(janitor) do
        if j.name == name then return end
    end
    table.insert(janitor, { name = name, nextAt = 0, tries = 0 })
end

Events.OnTick.Add(function()
    if #janitor == 0 then return end
    local now = getTimestampMs()
    for i = #janitor, 1, -1 do
        local j = janitor[i]
        if now >= j.nextAt then
            local busy = false
            for _, pr in ipairs(pendingResets) do
                if pr.tagRole == j.name then
                    busy = true
                    break
                end
            end
            if busy then
                -- a tracked reset still points at this role, deleting or
                -- moving it now would race the queued SetRole
                j.nextAt = now + 4000
            elseif wornOnline(j.name) then
                -- somebody online still wears it: the role is in active
                -- use, deleting would flip the wearer to plain user via
                -- the ungated deleteRole path. Stop chasing it
                print("[Aegis] tag: cleanup skipped, \"" .. tostring(j.name) .. "\" is still worn")
                table.remove(janitor, i)
            elseif engineRole(j.name) == nil then
                table.remove(janitor, i)
            elseif j.tries >= 10 then
                print("[Aegis] tag: cleanup gave up on stale role \"" .. tostring(j.name) .. "\"")
                table.remove(janitor, i)
            else
                j.tries = j.tries + 1
                if j.tries % 2 == 1 then
                    pcall(function() deleteRole(j.name) end)
                else
                    -- every moveRole triggers a full server side
                    -- Roles.save: keep pushes rare and NEVER press a role
                    -- under 1001, below that it slips under the banned
                    -- anchor and poisons every later rank check
                    local pos = nil
                    local r = engineRole(j.name)
                    if r then pos = r:getPosition() end
                    if pos ~= nil and pos > 1001 then
                        pcall(function() moveRole(-1, j.name) end)
                    end
                end
                j.nextAt = now + 4000
            end
        end
    end
end)

-- public wrapper around the janitor for other pages (role delete etc.);
-- the janitor itself keeps verifying by outcome
function AegisRoleTag.removeTagRole(name)
    cleanupRole(name)
end

-- recolor an existing head-tag role in place: setupRole with the same
-- marker and capabilities, only the color changes. Everyone currently
-- wearing the tag gets the new color via the role broadcast
function AegisRoleTag.recolorTagRole(name, color)
    if not AegisRoleTag.isTagRole(name) then return end
    if type(color) ~= "table" or not color.r then return end
    pcall(function()
        local r = engineRole(name)
        setupRole(r, MARKER, Color.new(color.r, color.g, color.b, 1.0), copyCaps(r))
    end)
end

-- true if the engine role carries our head tag marker
function AegisRoleTag.isTagRole(name)
    if not name then return false end
    local r = engineRole(name)
    if r == nil then return false end
    return not r:isReadOnly() and r:getDescription() == MARKER
end

-- move a player off his marked head-tag role back to a plain engine role.
-- SetRole has no return channel, so the flip is tracked like an
-- assignment (pendingResets) and the tag role is only janitor-deleted
-- after the flip is confirmed and no other online player still wears it
-- the engine draws the role name above the head when the role carries
-- ToggleWriteRoleNameAbove AND the player's own showAdminTag flag is set
-- (bytecode IsoGameCharacter.updateUserName). Dropping the tag role is
-- therefore only half the job for an ADMIN: his base role has the same
-- capability, so the plain "admin" text keeps showing. The flag can only
-- be set on the local player, which is exactly the case that matters
local function ownTagFlag(username, on)
    local me = getPlayer()
    if not me then return end
    local mine = me:getUsername()
    if mine == nil or mine ~= username then return end
    me:setShowAdminTag(on == true)
    Aegis.tagManualOff = not on
    Aegis.setPref("tagOff", on and "0" or "1")
end

function AegisRoleTag.resetPlayerTag(username)
    if not Aegis.canSee("roles") then return end
    local current = AegisRoleTag.currentRole(username)
    if not current or not AegisRoleTag.isTagRole(current) then return end
    if not isClient() then
        -- solo has no engine role catalog to fall back to, skip gracefully
        print("[Aegis] tag: reset skipped in solo for " .. tostring(username))
        return
    end
    local fallback = "user"
    pcall(function()
        local r = engineRole(current)
        if r and r:hasCapability(Capability.AdminTool) then fallback = "admin" end
    end)
    local ownPos, fbPos, tagPos = nil, nil, nil
    pcall(function()
        local mine = getPlayer():getRole()
        if mine then ownPos = mine:getPosition() end
    end)
    local r = engineRole(fallback)
    if r then fbPos = r:getPosition() end
    r = engineRole(current)
    if r then tagPos = r:getPosition() end
    -- gate 2 pre-flight: the server rejects any SetRole whose new role
    -- ranks above the requester, so climbing back UP (typically the own
    -- reset to admin after a self tag) is impossible from the client.
    -- Say so instead of burning silent attempts; restoring needs a higher
    -- ranked admin or the documented DB repair
    if ownPos ~= nil and fbPos ~= nil and fbPos > ownPos then
        print("[Aegis] tag: reset refused, fallback \"" .. fallback .. "\"@" .. tostring(fbPos) .. " ranks above own position " .. tostring(ownPos) .. " (server gate 2 would silently deny)")
        toast("UI_Aegis_HeadTagErrorSelfReset")
        return
    end
    -- gate 1 pre-flight: requester must rank at or above the target
    if ownPos ~= nil and tagPos ~= nil and tagPos > ownPos then
        print("[Aegis] tag: reset refused, target wears \"" .. tostring(current) .. "\"@" .. tostring(tagPos) .. " above own position " .. tostring(ownPos))
        toast("UI_Aegis_HeadTagErrorRank")
        return
    end
    for _, pr in ipairs(pendingResets) do
        if pr.username == username then return end
    end
    if lift and lift.name == current then
        print("[Aegis] tag: cancelling lift of \"" .. tostring(lift.name) .. "\" (reset takes over)")
        lift = nil
    end
    pcall(function() networkUserAction("SetRole", username, fallback) end)
    ownTagFlag(username, false)
    local now = getTimestampMs()
    print("[Aegis] tag: reset " .. tostring(username) .. " from \"" .. tostring(current) .. "\"@" .. tostring(tagPos) .. " to \"" .. fallback .. "\"@" .. tostring(fbPos))
    table.insert(pendingResets, {
        username = username,
        fallback = fallback,
        tagRole = current,
        attempts = 1,
        sentAt = now,
        nextAttempt = now + SETROLE_INTERVAL,
        deadline = now + SETROLE_ATTEMPTS * SETROLE_INTERVAL + 2000,
    })
end

Events.OnTick.Add(function()
    if #pendingResets == 0 then return end
    local now = getTimestampMs()
    for i = #pendingResets, 1, -1 do
        local pr = pendingResets[i]
        local current = AegisRoleTag.currentRole(pr.username)
        if current ~= nil and current ~= pr.tagRole then
            -- flip observed (fallback or whatever got assigned since)
            table.remove(pendingResets, i)
            print("[Aegis] tag: reset confirmed for " .. tostring(pr.username) .. " (now \"" .. tostring(current) .. "\") after " .. tostring(now - pr.sentAt) .. "ms")
            if nameCollides(pr.tagRole, pr.username) then
                print("[Aegis] tag: keeping role \"" .. tostring(pr.tagRole) .. "\", another online player still wears it")
            else
                cleanupRole(pr.tagRole)
            end
        elseif now >= pr.nextAttempt and pr.attempts < SETROLE_ATTEMPTS then
            pr.attempts = pr.attempts + 1
            pr.nextAttempt = now + SETROLE_INTERVAL
            print("[Aegis] tag: resend reset " .. tostring(pr.attempts) .. "/" .. tostring(SETROLE_ATTEMPTS) .. " for " .. tostring(pr.username) .. " (" .. tostring(now - pr.sentAt) .. "ms elapsed)")
            pcall(function() networkUserAction("SetRole", pr.username, pr.fallback) end)
        elseif now > pr.deadline then
            table.remove(pendingResets, i)
            if current == nil then
                -- forensic blind spot: with the target not resolvable the
                -- server stores the role DB-only without broadcast
                -- (getPlayerByUserName == null path), the reset may have
                -- landed and applies on the next login
                print("[Aegis] tag: reset unconfirmed, target " .. tostring(pr.username) .. " not resolvable; server may have stored the fallback DB-only (applies on next login)")
            else
                print("[Aegis] tag: reset unconfirmed after " .. tostring(pr.attempts) .. " attempts for " .. tostring(pr.username))
            end
            toast("UI_Aegis_HeadTagUnconfirmed")
        end
    end
end)

local MAX_PUSH = 50

Events.OnTick.Add(function()
    if not run then return end
    local now = getTimestampMs()
    if now < run.nextAt then return end
    run.nextAt = now + 350

    if now > run.deadline then
        cleanupRole(run.name)
        run = nil
        toast("UI_Aegis_HeadTagErrorTimeout")
        return
    end

    if run.step == "role" then
        local role = engineRole(run.name)
        if role ~= nil then
            local ok = pcall(function()
                setupRole(role, MARKER, Color.new(run.color.r, run.color.g, run.color.b, 1.0), run.caps)
            end)
            if not ok then
                run = nil
                toast("UI_Aegis_HeadTagError")
                return
            end
            run.step = "position"
        end
        return
    end

    if run.step == "position" then
        local role = engineRole(run.name)
        if role == nil then return end
        local pos = role:getPosition()

        -- re-read the target position EVERY time instead of using the
        -- earlier snapshot: updatePositions gives ALL non-read-only roles
        -- consecutive values in list order, so every own push also shifts
        -- the target's position. On self-assignment target and admin are
        -- even the same role, the old snapshot was already off after the
        -- first push ("role ranks above own" on
        -- self-tag)
        local targetNow = run.targetPosition
        local targetRole = run.target and run.target:getRole()
        if targetRole then targetNow = targetRole:getPosition() end

        -- never aim higher than the SAFE ceiling: only "read-only anchor
        -- plus one" positions are provably below the requester on the
        -- server, the order inside the own band is invisible to the
        -- client mirror (16 SetRole packets were silently denied
        -- although the mirror showed the role one rung below the own one)
        local ownNow = run.ownPosition
        if run.myRole then ownNow = run.myRole:getPosition() end
        local ceiling = safeCeiling(ownNow, run.ownReadOnly)
        if ceiling == nil then
            print("[Aegis] tag: abort mid-run, no safe anchor below own position " .. tostring(ownNow))
            cleanupRole(run.name)
            run = nil
            toast("UI_Aegis_HeadTagErrorLowBand")
            return
        end
        if ceiling < targetNow then targetNow = ceiling end

        -- acceptance window: at/above the target slot but NEVER above the
        -- safe ceiling. An overshot role from an earlier run must be
        -- pushed back DOWN (moveRole(-1), vanilla ISRolesList "DOWN"
        -- action) instead of being accepted as already positioned
        local upperBound = ceiling
        if pos >= targetNow and pos <= upperBound then
            -- do NOT assign straight away: the locally visible position can
            -- lag ~1.4s behind the server (client read
            -- 6001 and assigned while the server catalog already said 7002
            -- from a still-in-flight duplicate push). Settle first: only
            -- when the position stays unchanged for the settle window is it
            -- trustworthy; any drift falls back into positioning, which can
            -- push back down since the overshoot fix
            print("[Aegis] tag: position ok (" .. tostring(pos) .. "), settling")
            run.step = "settle"
            run.settlePos = pos
            run.settleUntil = now + 2200
            return
        end
        if run.pushAttempts >= MAX_PUSH then
            cleanupRole(run.name)
            run = nil
            toast("UI_Aegis_HeadTagErrorPosition")
            return
        end
        -- wait until the previous push has really arrived (position value
        -- changed) or a generous deadline has passed, otherwise several
        -- pushes fire blindly before their effect becomes visible and the
        -- role overshoots the target
        if run.posBeforePush ~= nil and pos == run.posBeforePush and now < (run.pushUntil or 0) then
            return
        end
        run.pushAttempts = run.pushAttempts + 1
        run.posBeforePush = pos
        -- wide resend window: every push triggers a full server side
        -- Roles.save, and stacked saves are exactly what delayed the
        -- SetRole processing by 25 to 60 seconds; one push per
        -- observed effect, not per timer tick
        run.pushUntil = now + 5000
        local direction = (pos > upperBound) and -1 or 1
        print("[Aegis] tag: push " .. (direction == 1 and "up" or "down") .. " from " .. tostring(pos) .. " (target " .. tostring(targetNow) .. ", ceiling " .. tostring(upperBound) .. ")")
        pcall(function() moveRole(direction, run.name) end)
        return
    end

    if run.step == "settle" then
        local role = engineRole(run.name)
        if role == nil then return end
        local pos = role:getPosition()
        if pos ~= run.settlePos then
            -- a late broadcast moved the role after we thought we were
            -- done - back to positioning (which can also push down)
            print("[Aegis] tag: drift during settle (" .. tostring(run.settlePos) .. " -> " .. tostring(pos) .. "), repositioning")
            run.step = "position"
            run.posBeforePush = nil
            return
        end
        -- positions are unique once converged, so reading the role at or
        -- above the own role means a double push parked it too high
        -- (settle read 6001 while the server already said 6002); back
        -- to positioning, which pushes it down again
        local ownPos = nil
        pcall(function()
            local mine = getPlayer():getRole()
            if mine then ownPos = mine:getPosition() end
        end)
        if ownPos and pos >= ownPos then
            print("[Aegis] tag: settle rank conflict (role " .. tostring(pos) .. " vs own " .. tostring(ownPos) .. "), repositioning")
            run.step = "position"
            run.posBeforePush = nil
            return
        end
        if now >= run.settleUntil then
            print("[Aegis] tag: settled at " .. tostring(pos) .. ", assigning")
            run.step = "assign"
        end
        return
    end

    if run.step == "assign" then
        local role = engineRole(run.name)
        local ownRole = nil
        pcall(function() ownRole = getPlayer():getRole() end)
        local pos = role and role:getPosition()
        local ownPosNow = ownRole and ownRole:getPosition()
        -- the server enforces its position gate for EVERYONE, including
        -- self-assignment (GameServer.changeRole gate 2, bytecode-verified
        -- and live-confirmed). A role read at or above the requester means
        -- a late broadcast still revealed a double push; positioning knows
        -- how to push the role back down, the run deadline caps retries
        if pos and ownPosNow and pos > ownPosNow then
            print("[Aegis] tag: rank conflict at assign (role " .. tostring(pos) .. " above requester " .. tostring(ownPosNow) .. "), repositioning")
            run.step = "position"
            run.posBeforePush = nil
            return
        end
        -- fetch the username fresh from the live player object instead of
        -- the originally passed string: the server resolves
        -- networkUserAction("SetRole", ...) in GameServer.changeRole via
        -- getPlayerByUserName (bytecode-verified, case matters exactly).
        -- If it does NOT find the player it only stores the role silently
        -- in the database, WITHOUT live update or broadcast, and no error
        -- comes back (assignment "unconfirmed", own
        -- head tag stayed "admin"). getUsername on the real object is
        -- guaranteed to be exactly the string the server knows
        local username = run.username
        pcall(function()
            if run.isSelf then
                username = getPlayer():getUsername()
            elseif run.target then
                username = run.target:getUsername()
            end
        end)
        print("[Aegis] tag: SetRole user=" .. tostring(username) .. " role=\"" .. tostring(run.name) .. "\" rolePos=" .. tostring(pos) .. " ownPos=" .. tostring(ownPosNow) .. " self=" .. tostring(run.isSelf))
        local l = run
        run = nil
        local ok = pcall(function() networkUserAction("SetRole", username, l.name) end)
        if not ok then
            toast("UI_Aegis_HeadTagError")
            return
        end
        pendingConfirm = {
            username = username,
            name = l.name,
            isSelf = l.isSelf == true,
            liftTarget = l.liftTarget,
            previousRole = l.previousRole,
            attempts = 1, -- the one just sent counts
            maxAttempts = SETROLE_ATTEMPTS,
            sentAt = now,
            slowToastAt = now + 30000,
            nextAttempt = now + SETROLE_INTERVAL,
            deadline = now + SETROLE_ATTEMPTS * SETROLE_INTERVAL + 2000,
            -- self assignments never demote: the park position is already
            -- provably below the requester (safeCeiling), an unconfirmed
            -- self run only means the server is slow, accepts have
            -- been seen arriving 25 to 60 seconds after
            -- sending while the old demote cycles flooded Roles.save and
            -- pressed the LIVE own rank down to 1001, sabotaging every
            -- following attempt. Foreign assignments keep a guarded
            -- demote as last resort
            demoteCycles = l.isSelf and 0 or 3,
        }
        return
    end
end)

-- another SetRole attempt, but only while the role is provably still in the
-- server-confirmed catalog, otherwise changeRole would run into the same
-- uncaught NPE again instead of a clean error text
local function resendSetRole(b)
    if engineRole(b.name) == nil then return end
    local username = b.username
    if b.isSelf then
        local p = getPlayer()
        if p then username = p:getUsername() end
    end
    pcall(function() networkUserAction("SetRole", username, b.name) end)
end

Events.OnTick.Add(function()
    if not pendingConfirm then return end
    local b = pendingConfirm
    local now = getTimestampMs()
    local current = AegisRoleTag.currentRole(b.username)
    if current == b.name then
        pendingConfirm = nil
        -- measured acceptance latency: the forensic gap was that accepts
        -- arriving 25 to 60 seconds late looked identical to silent
        -- denials, so the real number goes to the log every time
        print("[Aegis] tag: confirmed \"" .. b.name .. "\" for " .. tostring(b.username) .. " after " .. tostring(now - (b.sentAt or now)) .. "ms and " .. tostring(b.attempts) .. " SetRole attempt(s)")
        toast("UI_Aegis_HeadTagDone", b.name)
        -- tagging yourself has to switch the flag back ON, an earlier
        -- removal (or the powers page) may have turned it off
        ownTagFlag(b.username, true)
        Aegis.logAction("roles", string.format("Head tag \"%s\" assigned to %s", b.name, b.username))
        -- clean up the old head-tag role created only for this player,
        -- now that the new one is safely active
        if b.previousRole and nameCollides(b.previousRole, b.username) then
            print("[Aegis] tag: keeping role \"" .. tostring(b.previousRole) .. "\", another online player still wears it")
        else
            cleanupRole(b.previousRole)
        end
        if b.isSelf and b.liftTarget then
            -- pure Roles edit, no SetRole involved: nudge the now worn
            -- role back to the top of the band under the old own band so
            -- repeated self changes do not ratchet the own rank down
            lift = { name = b.name, target = b.liftTarget, tries = 0, stalls = 0, lastPos = nil, nextAt = now + 4000 }
            print("[Aegis] tag: lifting \"" .. b.name .. "\" towards " .. tostring(b.liftTarget))
        end
        return
    end
    -- honest interim signal: the server IS allowed to answer this late
    if b.slowToastAt and now >= b.slowToastAt then
        b.slowToastAt = nil
        print("[Aegis] tag: still unconfirmed after 30s, server is processing slowly (SetRole serializes behind queued Roles.save)")
        toast("UI_Aegis_HeadTagSlowServer")
    end
    -- not confirmed yet: resend at intervals while the role still exists
    -- (see resendSetRole) and the budget is not used up
    if now >= b.nextAttempt and b.attempts < (b.maxAttempts or SETROLE_ATTEMPTS) then
        b.attempts = b.attempts + 1
        b.nextAttempt = now + SETROLE_INTERVAL
        print("[Aegis] tag: resend SetRole " .. tostring(b.attempts) .. "/" .. tostring(b.maxAttempts or SETROLE_ATTEMPTS) .. " for " .. tostring(b.username) .. " (" .. tostring(now - (b.sentAt or now)) .. "ms elapsed, current role " .. tostring(current) .. ")")
        resendSetRole(b)
        return
    end
    if now > b.deadline then
        if current == nil then
            -- forensic blind spot: with the target not resolvable the
            -- server stores the role DB-only without any broadcast
            -- (getPlayerByUserName == null path), so the assignment may
            -- in fact have landed and applies on the next login
            print("[Aegis] tag: target " .. tostring(b.username) .. " not resolvable any more; server may have written the role DB-only (applies on next login)")
        end
        if (b.demoteCycles or 0) > 0 and not b.isSelf and current ~= nil and engineRole(b.name) ~= nil then
            local pos = nil
            local r = engineRole(b.name)
            if r then pos = r:getPosition() end
            -- never press a role under 1001, below that it slips under
            -- the banned anchor (exactly these demotes
            -- pushed the worn role, and with it the own live rank, to
            -- 1001 and killed every following attempt)
            if pos ~= nil and pos > 1001 then
                b.demoteCycles = b.demoteCycles - 1
                print("[Aegis] tag: unconfirmed, pushing \"" .. tostring(b.name) .. "\" one rung down from " .. tostring(pos) .. " and retrying (" .. tostring(b.demoteCycles) .. " cycles left)")
                pcall(function() moveRole(-1, b.name) end)
                b.attempts = 0
                -- shorter budget per demote cycle, the long first budget
                -- already covered the plain slow-server case
                b.maxAttempts = 6
                b.nextAttempt = now + SETROLE_INTERVAL
                b.deadline = now + 6 * SETROLE_INTERVAL + 2000
                return
            end
            print("[Aegis] tag: skipping demote for \"" .. tostring(b.name) .. "\" at position " .. tostring(pos) .. " (floor is 1001)")
        end
        pendingConfirm = nil
        print("[Aegis] tag: unconfirmed after " .. tostring(b.attempts) .. " SetRole attempts and " .. tostring(now - (b.sentAt or now)) .. "ms for " .. tostring(b.username))
        toast("UI_Aegis_HeadTagUnconfirmed")
    end
end)

-- gentle post-confirm lift of a self worn tag role: one moveRole(+1) per
-- OBSERVED position change, verified by outcome, so the server never sees
-- a Roles.save flood. Best effort only, the tag already sits; a failed
-- lift merely parks the own rank one band lower until the next change
Events.OnTick.Add(function()
    if not lift then return end
    local now = getTimestampMs()
    if now < lift.nextAt then return end
    lift.nextAt = now + 5000
    local r = engineRole(lift.name)
    if r == nil then
        lift = nil
        return
    end
    local pos = r:getPosition()
    if pos == nil then
        lift = nil
        return
    end
    if pos >= lift.target then
        print("[Aegis] tag: lift done, \"" .. lift.name .. "\" now at " .. tostring(pos))
        lift = nil
        return
    end
    if lift.lastPos ~= nil and pos == lift.lastPos then
        -- previous push not visible yet, wait instead of stacking moves
        lift.stalls = lift.stalls + 1
        if lift.stalls >= 10 then
            print("[Aegis] tag: lift gave up for \"" .. lift.name .. "\" at " .. tostring(pos) .. " (target " .. tostring(lift.target) .. ", no movement observed)")
            lift = nil
        end
        return
    end
    lift.stalls = 0
    if lift.tries >= 12 then
        print("[Aegis] tag: lift gave up for \"" .. lift.name .. "\" at " .. tostring(pos) .. " (target " .. tostring(lift.target) .. ", push budget spent)")
        lift = nil
        return
    end
    lift.tries = lift.tries + 1
    lift.lastPos = pos
    print("[Aegis] tag: lift push up from " .. tostring(pos) .. " (target " .. tostring(lift.target) .. ")")
    pcall(function() moveRole(1, lift.name) end)
end)


-- ---------- tag visibility guard ----------
-- the engine computes the sent tag bit from the active admin powers
-- alone (IsoPlayer.calculateShowAdminTag), the flag itself never
-- travels. So the server keeps a hide list, and every client re-applies
-- list and tag roles to its local copies; showAdminTag is a bare field
-- write, nothing goes over the wire
AegisRoleTag.hidden = {}
local hideAnswered = false
local verdictCache = {}

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= AegisShared.MODULE or command ~= "tagHide" then return end
    local set = {}
    for _, n in ipairs(args and args.names or {}) do set[tostring(n)] = true end
    AegisRoleTag.hidden = set
    -- keep the local pin in step, it holds the own flag between ticks
    local me = getPlayer()
    local mine = me and me:getUsername()
    if mine then
        -- first answer on a server that has no list yet: a hide kept only
        -- in the local prefs would be dropped here, so send it up once
        -- instead of taking the empty list for an answer
        if not hideAnswered then
            hideAnswered = true
            if Aegis.tagManualOff and not set[mine] then
                set[mine] = true
                sendClientCommand(me, AegisShared.MODULE, "tagHide", { on = true })
                return
            end
        end
        Aegis.tagManualOff = set[mine] == true
    end
end)

local function applyTag(p, mine)
    local name = p:getUsername()
    if not name then return end
    if AegisRoleTag.hidden[name] then
        if p:isShowAdminTag() then p:setShowAdminTag(false) end
        return
    end
    local role = p:getRole()
    local rname = role and role:getName() or nil
    if rname == nil then return end
    local v = verdictCache[name]
    if v == nil or v.role ~= rname then
        v = { role = rname, is = AegisRoleTag.isTagRole(rname) }
        verdictCache[name] = v
    end
    if not v.is then return end
    -- the own manual off wins over the tag role, the pin keeps it down
    if name == mine and Aegis.tagManualOff then return end
    if not p:isShowAdminTag() then p:setShowAdminTag(true) end
end

local hideNextTry = 0
local hideTries = 0
local HIDE_MAX_TRIES = 5

Events.OnTick.Add(function()
    local me = getPlayer()
    if not me then return end
    local mine = me:getUsername()
    if isClient() then
        local now = getTimestampMs()
        if not hideAnswered and hideTries < HIDE_MAX_TRIES and now >= hideNextTry then
            hideTries = hideTries + 1
            hideNextTry = now + 4000
            sendClientCommand(me, AegisShared.MODULE, "tagHideReq", {})
        end
        local players = getOnlinePlayers()
        if players then
            for i = 0, players:size() - 1 do
                local p = players:get(i)
                if p then applyTag(p, mine) end
            end
        end
    end
    applyTag(me, mine)
end)
