-- color palette and drawing helpers for the Aegis UI
require "ISUI/ISPanel"

Aegis = Aegis or {}
Aegis.version = "2.5.1"

-- admin night vision: client-local climate overrides lift the darkness for
-- THIS admin only (scenario override path, never broadcast). Off restores
-- the real lighting
Aegis.nightVision = false

local function nightVisionApply(on, interp)
    pcall(function()
        local cm = getClimateManager()
        local night = cm:getClimateFloat(ClimateManager.FLOAT_NIGHT_STRENGTH)
        local ambient = cm:getClimateFloat(ClimateManager.FLOAT_AMBIENT)
        night:setEnableOverride(on)
        ambient:setEnableOverride(on)
        if on then
            night:setOverride(0, interp)
            ambient:setOverride(0.85, interp)
        end
    end)
end

function Aegis.setNightVision(on)
    Aegis.nightVision = on == true
    nightVisionApply(Aegis.nightVision, 1)
end

-- keeper: the climate recomputes every ten in-game minutes and briefly
-- pushed its own dark values between the old 1.5s renewals (visible
-- dark flash). Pin the overrides EVERY tick with zero
-- interpolation instead; four java setters per frame cost nothing.
-- Only the initial enable still fades in softly via setNightVision.
-- tiny client preference file, K|V lines, survives restarts (same file
-- pattern as the custom builder pieces)
local PREFS_FILE = "AegisPrefs.txt"
local prefs = nil

local function prefsLoad()
    if prefs then return prefs end
    prefs = {}
    pcall(function()
        local w = getFileWriter(PREFS_FILE, true, true)
        if w then w:close() end
    end)
    pcall(function()
        local reader = getFileReader(PREFS_FILE, true)
        if not reader then return end
        local line = reader:readLine()
        while line ~= nil do
            local k, v = string.match(line, "^([^|]+)|(.*)$")
            if k then prefs[k] = v end
            line = reader:readLine()
        end
        reader:close()
    end)
    return prefs
end

function Aegis.getPref(key)
    return prefsLoad()[key]
end

function Aegis.setPref(key, value)
    prefsLoad()[key] = tostring(value)
    pcall(function()
        local w = getFileWriter(PREFS_FILE, true, false)
        if not w then return end
        for k, v in pairs(prefs) do
            w:write(k .. "|" .. v .. "\n")
        end
        w:close()
    end)
end

-- read at game start, not at boot: the Lua folder is only reliably
-- writable once a game is running
Events.OnGameStart.Add(function()
    prefs = nil
    Aegis.tagManualOff = prefsLoad()["tagOff"] == "1"
end)

Events.OnTick.Add(function()
    if Aegis.nightVision then nightVisionApply(true, 0) end
    -- manually hidden admin tag stays hidden: toggling powers flips the
    -- flag back on engine side, the pin undoes that until the switch in
    -- the powers page re-enables it
    if Aegis.tagManualOff then
        local p = getPlayer()
        if p and p:isShowAdminTag() then p:setShowAdminTag(false) end
    end
end)

local texCache = {}

function Aegis.tex(name)
    local t = texCache[name]
    if t == nil then
        t = getTexture("media/ui/Aegis/" .. name .. ".png") or false
        texCache[name] = t
    end
    if t == false then return nil end
    return t
end

Aegis.col = {
    bg      = { r = 0.075, g = 0.082, b = 0.098 },
    panel   = { r = 0.097, g = 0.105, b = 0.124 },
    card    = { r = 0.125, g = 0.135, b = 0.158 },
    cardHi  = { r = 0.163, g = 0.176, b = 0.204 },
    line    = { r = 0.205, g = 0.220, b = 0.253 },
    gold    = { r = 0.843, g = 0.647, b = 0.290 },
    goldHi  = { r = 0.941, g = 0.765, b = 0.416 },
    goldDim = { r = 0.480, g = 0.380, b = 0.185 },
    text    = { r = 0.910, g = 0.894, b = 0.855 },
    muted   = { r = 0.565, g = 0.555, b = 0.530 },
    danger  = { r = 0.804, g = 0.320, b = 0.278 },
    ok      = { r = 0.420, g = 0.690, b = 0.440 },
    dark    = { r = 0.055, g = 0.060, b = 0.072 },
    white   = { r = 1, g = 1, b = 1 },
}

-- frame delta normalized to 30 FPS, capped against stutter
function Aegis.delta()
    local d = UIManager.getMillisSinceLastRender() / 33.3
    if d > 3 then d = 3 end
    return d
end

-- smooth, framerate independent transition towards a target value
function Aegis.glide(cur, target, rate)
    local t = rate * Aegis.delta()
    if t > 1 then t = 1 end
    local v = cur + (target - cur) * t
    if math.abs(target - v) < 0.002 then return target end
    return v
end

-- filled rectangle with rounded corners built from quarter circle textures
function Aegis.roundRect(el, x, y, w, h, r, a, c)
    local half = math.floor(math.min(w, h) / 2)
    if r > half then r = half end
    if r < 1 then
        el:drawRect(x, y, w, h, a, c.r, c.g, c.b)
        return
    end
    el:drawTextureScaled(Aegis.tex("cnr_tl"), x, y, r, r, a, c.r, c.g, c.b)
    el:drawTextureScaled(Aegis.tex("cnr_tr"), x + w - r, y, r, r, a, c.r, c.g, c.b)
    el:drawTextureScaled(Aegis.tex("cnr_bl"), x, y + h - r, r, r, a, c.r, c.g, c.b)
    el:drawTextureScaled(Aegis.tex("cnr_br"), x + w - r, y + h - r, r, r, a, c.r, c.g, c.b)
    if w > 2 * r then
        el:drawRect(x + r, y, w - 2 * r, r, a, c.r, c.g, c.b)
        el:drawRect(x + r, y + h - r, w - 2 * r, r, a, c.r, c.g, c.b)
    end
    if h > 2 * r then
        el:drawRect(x, y + r, w, h - 2 * r, a, c.r, c.g, c.b)
    end
end

-- rounded frame: border color underneath, fill inset by 1px on top
function Aegis.roundFrame(el, x, y, w, h, r, a, cBorder, cFill)
    Aegis.roundRect(el, x, y, w, h, r, a, cBorder)
    Aegis.roundRect(el, x + 1, y + 1, w - 2, h - 2, math.max(1, r - 1), a, cFill)
end

function Aegis.icon(el, name, x, y, size, a, c)
    local t = Aegis.tex("ico_" .. name)
    if t then
        el:drawTextureScaled(t, x, y, size, size, a, c.r, c.g, c.b)
    end
end

-- soft drop shadow behind panels
function Aegis.shadow(el, x, y, w, h, spread, a)
    local t = Aegis.tex("glow")
    if t then
        el:drawTextureScaled(t, x - spread, y - spread + 6, w + spread * 2, h + spread * 2, a, 0, 0, 0)
    end
end

function Aegis.hairline(el, x, y, w, a)
    el:drawRect(x, y, w, 1, a or 1, Aegis.col.line.r, Aegis.col.line.g, Aegis.col.line.b)
end

function Aegis.text(el, str, x, y, font, c, a)
    el:drawText(str, x, y, c.r, c.g, c.b, a or 1, font)
end

function Aegis.textCentre(el, str, x, y, font, c, a)
    el:drawTextCentre(str, x, y, c.r, c.g, c.b, a or 1, font)
end

function Aegis.textRight(el, str, x, y, font, c, a)
    el:drawTextRight(str, x, y, c.r, c.g, c.b, a or 1, font)
end

function Aegis.fontH(font)
    return getTextManager():getFontHeight(font)
end

function Aegis.strW(font, str)
    return getTextManager():MeasureStringX(font, str)
end

-- trim text to width, long mod option names otherwise run under the controls
function Aegis.fitText(str, font, maxW)
    if not str or str == "" then return "" end
    if Aegis.strW(font, str) <= maxW then return str end
    local s = str
    while string.len(s) > 1 and Aegis.strW(font, s .. "..") > maxW do
        s = string.sub(s, 1, string.len(s) - 1)
        -- drop trailing UTF-8 continuation bytes at the cut (umlauts)
        while string.len(s) > 1 do
            local b = string.byte(s, string.len(s))
            if b and b >= 128 and b < 192 then
                s = string.sub(s, 1, string.len(s) - 1)
            else
                break
            end
        end
    end
    return s .. ".."
end

-- byte index right after the UTF-8 character that starts at i
local function charEnd(str, i)
    local n = string.len(str)
    local j = i + 1
    while j <= n do
        local b = string.byte(str, j)
        if b < 128 or b >= 192 then break end
        j = j + 1
    end
    return j
end

-- hard break for a run that is wider than the line on its own. Chinese,
-- Japanese, Korean and Thai arrive as one single run because they carry no
-- spaces, so this path is the normal case for them. Cuts land on UTF-8
-- sequence starts only, a cut inside a multi byte character would render as
-- garbage. Every pass consumes at least one character, so the loop always
-- ends even when not a single character fits
local function splitRun(out, run, font, maxW)
    local n = string.len(run)
    local i = 1
    while i <= n do
        local cut = nil
        local j = i
        while j <= n do
            local nxt = charEnd(run, j)
            if Aegis.strW(font, string.sub(run, i, nxt - 1)) > maxW then break end
            cut = nxt
            j = nxt
        end
        if not cut then cut = charEnd(run, i) end
        table.insert(out, string.sub(run, i, cut - 1))
        i = cut
    end
end

-- upper bound against pathological input, no dialog ever needs this many
local WRAP_CAP = 64

-- wrap a string to a pixel width and return the lines. Breaks at word
-- boundaries, falls back to the character level for over long runs and keeps
-- line breaks that are already in the text. maxLines is optional: the last
-- visible line then absorbs the rest and is trimmed by fitText
function Aegis.wrapText(str, font, maxW, maxLines)
    if str == nil then return { "" } end
    str = tostring(str)
    if not maxW or maxW < 8 then return { str } end
    local lines = {}
    local flat = string.gsub(str, "\r", "")
    for raw in string.gmatch(flat .. "\n", "([^\n]*)\n") do
        local cur = ""
        for word in string.gmatch(raw, "%S+") do
            local cand = (cur == "") and word or (cur .. " " .. word)
            if Aegis.strW(font, cand) <= maxW then
                cur = cand
            else
                if cur ~= "" then
                    table.insert(lines, cur)
                    cur = ""
                end
                if Aegis.strW(font, word) <= maxW then
                    cur = word
                else
                    local pieces = {}
                    splitRun(pieces, word, font, maxW)
                    for k = 1, #pieces - 1 do table.insert(lines, pieces[k]) end
                    cur = pieces[#pieces] or ""
                end
            end
            if #lines >= WRAP_CAP then break end
        end
        table.insert(lines, cur)
        if #lines >= WRAP_CAP then break end
    end
    if #lines == 0 then lines[1] = "" end
    if maxLines and maxLines >= 1 and #lines > maxLines then
        -- two following lines are enough to force the trim marker, joining
        -- the whole remainder would make fitText walk a huge string
        local merged = lines[maxLines]
        for i = maxLines + 1, math.min(#lines, maxLines + 2) do
            if lines[i] ~= "" then merged = merged .. " " .. lines[i] end
        end
        lines[maxLines] = Aegis.fitText(merged, font, maxW)
        for i = #lines, maxLines + 1, -1 do
            table.remove(lines, i)
        end
    end
    return lines
end

function Aegis.sound()
    getSoundManager():playUISound("UIActivateButton")
end

-- read in-game clock MP-safe: getHour/getMinutes read GameTime.timeOfDay,
-- which after a big jump (Aegis time set) only catches up smoothly over
-- several in-game minutes (same smoothing that absorbs small net drift). The
-- vanilla clock (zombie.ui.Clock, bytecode verified) instead reads the public
-- field GameTime.serverTimeOfDay, which is correct immediately. In MP we read
-- the same field; in solo there is no server/client split and serverTimeOfDay
-- stays unused (0), so getHour stays correct there
function Aegis.hourMinute(gt)
    gt = gt or getGameTime()
    if isClient() then
        local ok, value = pcall(function() return gt.serverTimeOfDay end)
        if ok and type(value) == "number" and value >= 0 then
            local hour = math.floor(value) % 24
            local minute = math.floor((value - math.floor(value)) * 60)
            return hour, minute
        end
    end
    return gt:getHour(), gt:getMinutes()
end

-- in-game calendar date as "DD.MM.YYYY": do NOT use getNightsSurvived, that
-- is a pure survival tick counter (bytecode: setDay/setMonth/setYear never
-- touch it) and freezes after an admin date jump even though the calendar
-- changed, which made the old "day N" display confusing. The day/month/year
-- fields themselves are plain integers without smoothing, correct right after
-- the timeSync broadcast (AegisPageWorld.lua).
function Aegis.dateText(gt)
    gt = gt or getGameTime()
    return string.format("%02d.%02d.%d", gt:getDayPlusOne(), gt:getMonth() + 1, gt:getYear())
end

-- combined line "day N, DD.MM.YYYY": user wants the survival day
-- (getNightsSurvived+1, pure counter since run start) shown IN ADDITION to
-- the real calendar date, not as a replacement. Separator is deliberately a
-- plain comma: the middle dot U+00B7 is missing from the game's bitmap font and renders as "?"
-- (user find)
function Aegis.dayAndDate(gt)
    gt = gt or getGameTime()
    local day = gt:getNightsSurvived() + 1
    local date = Aegis.dateText(gt)
    if date ~= "" then
        return getText("UI_Aegis_Day") .. " " .. tostring(day) .. ", " .. date
    end
    return date
end

-- log relay for actions without their own Aegis server command (Java cheats,
-- vanilla slash commands, solo direct paths): the loopback fires the
-- logAction handler in singleplayer too, logging always happens server side
function Aegis.logAction(area, text)
    local p = getPlayer()
    if not p or not text or text == "" then return end
    pcall(function()
        sendClientCommand(p, AegisShared.MODULE, "logAction", { area = area, text = text })
    end)
end

-- location teleport that keeps the vehicle: seated admins route through
-- the Aegis server command (validated there, the player teleports first
-- and the server pulls vehicle and trailer after him, staged replies in
-- AegisHud.lua), everyone else gets the plain player teleport. username
-- targets resolve their position server side, the coordinate fallback
-- then uses the vanilla /teleport
function Aegis.teleportSmart(x, y, z, username)
    local p = getPlayer()
    if not p then return end
    local inVehicle = p:getVehicle() ~= nil
    if inVehicle then
        local args
        if username then
            args = { username = tostring(username) }
        else
            args = { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) }
        end
        pcall(function()
            sendClientCommand(p, AegisShared.MODULE, "teleportVehicle", args)
        end)
        return
    end
    if username then
        local safe = tostring(username):gsub("%c", " "):gsub("[\"\\]", " ")
        SendCommandToServer("/teleport \"" .. safe .. "\"")
        return
    end
    if isClient() then
        SendCommandToServer("/teleportto " .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z or 0))
    else
        p:teleportTo(x, y, (z or 0) + 0.0)
    end
end

-- capability check: always allowed in solo, in MP via the B42 role system
function Aegis.hasCap(capName)
    if not isClient() then return true end
    local ok, res = pcall(function()
        local p = getPlayer()
        if not p then return false end
        local role = p:getRole()
        if not role then return false end
        local cap = Capability[capName]
        if not cap then return false end
        return role:hasCapability(cap)
    end)
    return ok and res == true
end

-- What the admin last left standing through OUR panel. Vanilla re-grants
-- godmode, invisibility and noclip on its own every time a character gains
-- an admin level, which undoes a deliberate "off" without asking. To be
-- able to put that back without also fighting the admin's own choice, the
-- three states are recorded whenever a power was toggled here: syncPowers
-- runs after every toggle on the dashboard and on the powers page, so
-- whatever stands at that moment IS the intent
Aegis.powerIntent = Aegis.powerIntent or {}

function Aegis.notePowerIntent(player)
    Aegis.powerIntent.god = player:isGodMod() == true
    Aegis.powerIntent.invisible = player:isInvisible() == true
    Aegis.powerIntent.noclip = player:isNoClip() == true
end

-- batched sync of admin powers to the server, pattern from ISAdminPowerUI
function Aegis.syncPowers(player)
    if not isClient() then return end
    Aegis.notePowerIntent(player)
    pcall(function()
        if not player:isDead() and player:getRole() and player:getRole():hasAdminPower() then
            sendPlayerExtraInfo(player)
        end
    end)
end

-- solo: the cheat setters on the player check Role.hasCapability, but in
-- singleplayer Roles.init never runs (only the server loads the role DB),
-- getRole is nil and every setter forces false. So build our own role with
-- all capabilities (Role is exposed to Lua) and assign it once.
function Aegis.ensureSoloRole()
    if isClient() or isServer() then return end
    pcall(function()
        local p = getPlayer()
        if not p then return end
        local role = p:getRole()
        if role and role:hasCapability(Capability.ToggleGodModHimself)
            and role:hasCapability(Capability.ToggleUnlimitedAmmo) then
            return
        end
        if not Aegis.soloRole then
            local full = Role.new("aegis")
            local caps = getCapabilities()
            for i = 0, caps:size() - 1 do
                full:addCapability(caps:get(i))
            end
            Aegis.soloRole = full
        end
        p:setRole(Aegis.soloRole)
        p:setShowAdminTag(false)
    end)
end

-- shared tooltip pattern (modeled on ISButton:updateTooltip), usable by any
-- Aegis widget that carries a .tooltip field; call from prerender
-- same machinery, but text and position come from the caller. Rows of a
-- list are drawn and not elements of their own, so they have no tooltip
-- field the version below could find
function Aegis.updateTooltipAt(el, text, x, y)
    if text and text ~= "" then
        if not el.tooltipUI then
            el.tooltipUI = ISToolTip:new()
            el.tooltipUI:setOwner(el)
            el.tooltipUI:setVisible(false)
            el.tooltipUI:setAlwaysOnTop(true)
        end
        if not el.tooltipUI:getIsVisible() then
            el.tooltipUI.maxLineWidth = 280
            el.tooltipUI:addToUIManager()
            el.tooltipUI:setVisible(true)
        end
        el.tooltipUI.description = text
        el.tooltipUI:setDesiredPosition(x, y)
    elseif el.tooltipUI and el.tooltipUI:getIsVisible() then
        el.tooltipUI:setVisible(false)
        el.tooltipUI:removeFromUIManager()
    end
end

function Aegis.updateTooltip(el)
    local show = (el:isMouseOver() or el.joypadFocused) and el.tooltip or nil
    Aegis.updateTooltipAt(el, show, getMouseX(), el:getAbsoluteY() + el:getHeight() + 8)
end

-- short golden confirmation at the top of the window, for actions without a
-- visible result of their own (heal, repair, apply sandbox, ...).
-- The header is invisible whenever the window is hidden (photo mode, the
-- world editors, the restore preview), and those are exactly the moments
-- a denial has to reach the admin, so fall back to floating world text
-- (a refused restore looked like a dead button because the
-- message went into a hidden header)
function Aegis.showToast(text)
    local win = AegisWindow.instance
    if win and win:isVisible() then
        win.toastText = text
        win.toastUntil = getTimestampMs() + 2200
        return
    end
    -- exactly the two argument overload: javap lists addText(IsoPlayer,
    -- String) but no (IsoPlayer, String, ColorRGB), and Kahlua throws on
    -- a signature that does not exist
    pcall(function()
        HaloTextHelper.addText(getPlayer(), tostring(text))
    end)
end

-- Aegis rights reported by the server: nil = full access, false = no access,
-- otherwise table area = true. "nil" is also the initial value BEFORE any
-- server reply; without a separate loaded flag, "not synced yet" cannot be
-- told apart from the confirmed "vanilla admin without assignment = full
-- access". rightsReq only goes out AFTER the window opens (network round
-- trip), but the window builds its page navigation immediately; until the
-- reply arrives EVERY player would briefly see all areas regardless of their
-- real role: a click in this window fired a real
-- privileged server command that got the client kicked as suspicious)
Aegis.rights = nil
Aegis.rightsLoaded = false
-- name of the assigned Aegis role, nil if none is assigned
Aegis.role = nil

function Aegis.canSee(area)
    if not isClient() then return true end
    local r = Aegis.rights
    if r == nil then
        -- "nil" only counts as full access after a real server reply,
        -- before that show nothing rather than too much (fail closed)
        return Aegis.rightsLoaded == true
    end
    -- Anti lockout, same yardstick as AegisRoles.canManageRoles on the
    -- server. It used to accept any level with the admin tool, which is
    -- far too wide: on the B42 role registry observer, gm and moderator
    -- all carry AdminTool, only "admin" carries RolesWrite. An observer
    -- could open this page and grant himself every area.
    -- A real admin still cannot lock himself out, everyone else needs
    -- the area granted through an Aegis role
    if area == "roles" and Aegis.hasCap("RolesWrite") then return true end
    if r == false then return false end
    return r[area] == true
end

-- true only once the SERVER has confirmed at least one area, false while
-- waiting for that answer. This is the safety net for Aegis.allowed below:
-- that check runs on the client's own, sometimes unreadable role registry
-- and fails open on purpose (locking out a real admin is worse), so a
-- misjudged custom rank can pass it and the icon would show. The server
-- always has a readable registry and never gets this wrong, so gating the
-- icon on ITS answer catches every such case, not just one renamed level
--
-- Solo has no server to send that answer, so it takes the same shortcut
-- canSee uses above
function Aegis.hasAnyArea()
    if not isClient() then return true end
    local r = Aegis.rights
    if r == nil then return Aegis.rightsLoaded == true end
    if r == false then return false end
    for _, granted in pairs(r) do
        if granted == true then return true end
    end
    return false
end

-- may this character see the suite: ONLY real vanilla admins (role with the
-- AdminTool capability, e.g. granted via /setaccess or the server user
-- management). A purely Aegis-internal role assignment without real vanilla
-- admin status is deliberately NOT enough anymore, only admins set via
-- /setaccess may see the icon at all. This
-- disables the earlier delegation option where an assigned Aegis role
-- without vanilla admin could open the suite.
function Aegis.allowed(chr)
    if not chr then return false end
    if isClient() then
        -- the level string alone is NOT enough: "user" is the default
        -- level of every normal player in B42 and head tag roles are
        -- levels too. The
        -- registry lookup resolves the level to its stable role object
        -- and reads hasAdminTool there
        local ok, res = pcall(function()
            local levelOk, level = pcall(function()
                return tostring(chr:getAccessLevel() or ""):lower()
            end)
            if levelOk then return AegisShared.levelIsAdmin(level) end
            local role = chr:getRole()
            return role and role:hasAdminTool() or false
        end)
        return ok and res == true
    end
    return not isServer()
end
