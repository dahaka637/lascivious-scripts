-- Lascivious Factions System - admin debug/testing tools (client side).
-- Gives an admin a god-mode surface to stand up factions, place claims anywhere,
-- populate rosters, and simulate raids WITHOUT a second player -- so the whole
-- framework (raids included) can be validated solo. Two entry points:
--   * FF.adminCommand(rest)  -- the "/ff admin ..." chat subcommands (routed from
--     LFS_Client.lua's handleFFCommand).
--   * a world right-click "Faction Admin" menu that operates on the active faction.
-- All of this only forwards intents; every mutation is validated/gated server-side
-- (see the adminHandler-wrapped Handlers in LFS_Server.lua). The menu
-- itself is also admin-gated so non-admins never see it.

require "LFS_Shared"
require "LFS_Claims"
require "LFS_Localization"

local FF = LasciviousFactionsSystem
local Claims = FF.Claims

-- Client-side scratch state: which faction the right-click menu acts on, and the
-- first corner of an in-progress rectangle selection. Not persisted.
FF.adminState = FF.adminState or { activeFaction = nil, cornerA = nil }

local function send(command, args)
    sendClientCommand(getPlayer(), FF.MODULE, command, args or {})
end

-- Local-only feedback (console + halo) for client-side commands.
local function output(text)
    text = FF.tr and FF.tr(text) or text
    print("[LFS] " .. text)
    local p = getPlayer()
    if p then p:setHaloNote(text, 255, 255, 255, 250) end
end

-- ---------------------------------------------------------------------------
-- /ff admin <sub> ...
-- ---------------------------------------------------------------------------
local ADMIN_USAGE =
    "/ff admin use <faction> | create <name> [owner] | disband <name> | "
    .. "addmember <faction> <user> [role] | removemember <faction> <user> | "
    .. "claimhere <faction> [size] | claim <faction> <x1> <y1> <x2> <y2> | "
    .. "rename <old> \"<new>\" | set <faction> tag|desc|motd|join|option|color ... | "
    .. "owner <faction> <username> | "
    .. "addrect <faction> <x1> <y1> <x2> <y2> | unclaim <faction> | "
    .. "unclaimhere [all] | purgeclaims | purge [all|refs|claims|dry] | "
    .. "respawn <faction> [x y z] | list | ally <A> <B> | enemy <A> <B> | neutral <A> <B> | "
    .. "raid <attacker> <defender> | "
    .. "simraid <defender> <attackers> <defenders> | capture <defender> | endraid <defender> | "
    .. "decay <faction> | "
    .. "stat <faction> <raidsWon|raidsLost|raidsDefended> <n> | "
    .. "score <player> <kills|hours> <n> | "
    .. "war [list|end|score] [A] [B] [n] | "
    .. "pact [list|clear] [A] [B] | "
    .. "season [status|end|restart] | "
    .. "noclaim list|here [size]|add <x1> <y1> <x2> <y2> [name]|zone \"<name>\"|rename <id> \"<name>\"|resize <id> ...|remove <id>|clear | "
    .. "uitest [width ...]"
    .. " -- quote names containing spaces: ally \"Test Faction\" Red"

local function adminUsage()
    return FF.text("UI_LFS_AdminUsage", ADMIN_USAGE)
end

-- Split a string into whitespace-separated tokens. Double-quoted runs stay one
-- token so faction names with spaces work: /ff admin ally "Test Faction" Red
local function tokens(s)
    local t = {}
    local i, n = 1, #(s or "")
    while i <= n do
        local c = string.sub(s, i, i)
        if c == " " or c == "\t" then
            i = i + 1
        elseif c == '"' then
            local close = string.find(s, '"', i + 1, true)
            if close then
                t[#t + 1] = string.sub(s, i + 1, close - 1)
                i = close + 1
            else
                t[#t + 1] = string.sub(s, i + 1)   -- unterminated quote: rest is one token
                i = n + 1
            end
        else
            local stop = string.find(s, "[ \t\"]", i) or (n + 1)
            t[#t + 1] = string.sub(s, i, stop - 1)
            i = stop
        end
    end
    return t
end

function FF.adminCommand(rest)
    local tk = tokens(rest)
    local sub = (tk[1] or ""):lower()

    if sub == "use" then
        if not tk[2] then
            FF.adminState.activeFaction = nil
            output("Admin: active faction cleared.")
        else
            FF.adminState.activeFaction = tk[2]
            output("Admin: active faction is now '" .. tk[2] .. "' (used by the right-click menu).")
        end
    elseif sub == "create" then
        send("adminCreate", { name = tk[2], owner = tk[3] })
    elseif sub == "disband" then
        send("adminDisband", { name = tk[2] })
    elseif sub == "rename" then
        send("adminRename", { name = tk[2], newName = tk[3] })
    elseif sub == "owner" then
        send("transferOwnership", { faction = tk[2], username = tk[3] })
    elseif sub == "set" then
        -- Drive any faction's own settings handlers as an admin. They are owner-gated
        -- for players; passing `faction` opts into the admin override (see ownerFaction).
        local f, field = tk[2], (tk[3] or ""):lower()
        if not f or f == "" then
            output(FF.text("UI_LFS_AdminUsageSetShort",
                "Usage: /ff admin set <faction> tag|desc|motd|option|color ..."))
        elseif field == "tag" then
            send("setFactionInfo", { faction = f, tag = tk[4] })
        elseif field == "desc" then
            send("setFactionInfo", { faction = f, description = tk[4] or "" })
        elseif field == "motd" then
            send("setFactionInfo", { faction = f, motd = tk[4] or "" })
        elseif field == "option" then
            send("setFactionOption", { faction = f, key = tk[4],
                value = (tk[5] == "on" or tk[5] == "true") })
        elseif field == "color" then
            -- Components are 0..1, matching setFactionColor's own clamp. "auto" clears
            -- the override and goes back to the name-derived colour.
            if (tk[4] or ""):lower() == "auto" then
                send("setFactionColor", { faction = f })
            else
                send("setFactionColor", { faction = f, r = tk[4], g = tk[5], b = tk[6] })
            end
        else
            output(FF.text("UI_LFS_AdminUsageSet",
                "Usage: /ff admin set <faction> tag <text> | desc <text> | motd <text> | "
                .. "join open|closed | option <key> on|off | color <r> <g> <b> (0..1) | color auto"))
        end
    elseif sub == "addmember" then
        send("adminAddMember", { name = tk[2], username = tk[3], role = tk[4] })
    elseif sub == "removemember" then
        send("adminRemoveMember", { name = tk[2], username = tk[3] })
    elseif sub == "claimhere" then
        send("adminClaimHere", { name = tk[2], size = tk[3] })
    elseif sub == "claim" then
        send("adminClaimRect", { name = tk[2], x1 = tk[3], y1 = tk[4], x2 = tk[5], y2 = tk[6] })
    elseif sub == "addrect" then
        send("adminClaimRect", { name = tk[2], x1 = tk[3], y1 = tk[4], x2 = tk[5], y2 = tk[6], add = true })
    elseif sub == "unclaim" then
        send("adminUnclaim", { name = tk[2] })
    elseif sub == "unclaimhere" then
        -- Whoever's claim you are standing in, no name needed. "all" for the whole
        -- claim rather than just the area under your feet.
        local p = getPlayer()
        if not p then return output("Admin: no player.") end
        send("adminRemoveClaimAt", {
            x = math.floor(p:getX()), y = math.floor(p:getY()),
            all = (tk[2] == "all") or nil,
        })
    elseif sub == "purgeclaims" then
        send("adminPurgeClaims", {})
    elseif sub == "purge" then
        -- all (default) | refs | claims | dry. `dry` reports without changing anything,
        -- which is what the startup warning tells admins to check with first.
        send("adminPurge", { what = tk[2] })
    elseif sub == "respawn" then
        send("adminSetRespawn", { name = tk[2], x = tk[3], y = tk[4], z = tk[5] })
    elseif sub == "list" then
        send("adminList", {})
    elseif sub == "ally" then
        send("adminSetRelation", { a = tk[2], b = tk[3], status = "ally" })
    elseif sub == "enemy" then
        send("adminSetRelation", { a = tk[2], b = tk[3], status = "enemy" })
    elseif sub == "neutral" then
        send("adminSetRelation", { a = tk[2], b = tk[3], status = "neutral" })
    elseif sub == "raid" then
        send("adminRaid", { attacker = tk[2], defender = tk[3] })
    elseif sub == "simraid" then
        send("adminSimRaid", { defender = tk[2], attackers = tk[3], defenders = tk[4] })
    elseif sub == "capture" then
        send("adminCapture", { defender = tk[2] })
    elseif sub == "endraid" then
        send("adminEndRaid", { defender = tk[2] })
    elseif sub == "decay" then
        send("adminDecay", { name = tk[2] })
    elseif sub == "stat" then
        send("adminStat", { name = tk[2], stat = tk[3], count = tk[4] })
    elseif sub == "score" then
        -- Adds to a PLAYER's own banked score (kills or hours), not a faction stat --
        -- see Handlers.adminScore. A faction's score is just the live sum of its
        -- current members' banked totals, so this is also how claim-size testing
        -- is driven without grinding zombies or waiting out the clock.
        send("adminScore", { name = tk[2], stat = tk[3], count = tk[4] })
    elseif sub == "war" then
        -- list wars/ceasefires, end <A> <B>, or score <A> <B> <n>.
        send("adminWar", { sub = tk[2], a = tk[3], b = tk[4], n = tk[5] })
    elseif sub == "pact" then
        -- list active pacts, or clear <A> <B>.
        send("adminPact", { sub = tk[2], a = tk[3], b = tk[4] })
    elseif sub == "season" then
        -- status (default), end (force rollover), or restart (reset clock/baseline).
        send("adminSeason", { sub = tk[2] })
    elseif sub == "noclaim" then
        -- Areas where no faction may claim land. `add`/`here` REMOVE any claim already
        -- overlapping the new zone -- the chat path does it without a prompt (the
        -- right-click menu confirms first). Get the coordinates right.
        local act = (tk[2] or "list"):lower()
        if act == "list" then
            send("adminNoClaimList", {})
        elseif act == "here" then
            send("adminNoClaimAdd", { size = tk[3], name = tk[4] })
        elseif act == "add" then
            send("adminNoClaimAdd", { x1 = tk[3], y1 = tk[4], x2 = tk[5], y2 = tk[6], name = tk[7] })
        elseif act == "zone" then
            send("adminNoClaimZone", { title = tk[3] })
        elseif act == "remove" then
            send("adminNoClaimRemove", { id = tk[3] })
        elseif act == "rename" then
            send("adminNoClaimRename", { id = tk[3], name = tk[4] })
        elseif act == "resize" then
            -- resize <id> [x1 y1 x2 y2] | resize <id> here [size]
            if (tk[4] or ""):lower() == "here" then
                send("adminNoClaimResize", { id = tk[3], size = tk[5] })
            else
                send("adminNoClaimResize", { id = tk[3], x1 = tk[4], y1 = tk[5], x2 = tk[6], y2 = tk[7] })
            end
        elseif act == "clear" then
            send("adminNoClaimClear", {})
        else
            output(FF.text("UI_LFS_AdminUsageNoClaim",
                "Usage: /ff admin noclaim list | here [size] [name] | add <x1> <y1> <x2> <y2> [name] | zone \"<zone name>\" | rename <id> \"<name>\" | resize <id> [x1 y1 x2 y2 | here [size]] | remove <id> | clear"))
        end
    elseif sub == "uitest" then
        -- Purely client-side: drives the open panel through every tab at several
        -- widths and reports overlapping controls / widgets escaping their parent.
        -- Findings go to the console; the halo carries the summary.
        if not FF.uiTest then
            output("uitest: LFS_UiTest.lua did not load.")
        else
            local widths = {}
            for i = 2, #tk do
                local n = tonumber(tk[i])
                if n and n > 0 then widths[#widths + 1] = math.floor(n) end
            end
            FF.uiTest(widths)
        end
    else
        output(adminUsage())
    end
end

-- ---------------------------------------------------------------------------
-- World right-click "Faction Admin" menu
-- ---------------------------------------------------------------------------
-- Always available to admins (no /ff admin use required first); clicked tile taken
-- from the first world object's square. Vanilla's isAdmin() is false for a coop
-- host (not a network client, access level unset), so gate like the server does:
-- coop host OR access level "admin". Single player also passes for easy testing.
local function isLocalAdmin()
    if isCoopHost() then return true end
    if not isClient() then return true end -- single player / debug session
    local al = getAccessLevel and getAccessLevel()
    return al ~= nil and string.lower(tostring(al)) == "admin"
end
-- Exposed so the panel can gate its own admin-only affordances on the same test.
FF.isLocalAdmin = isLocalAdmin

-- Yes/no modal in front of a destructive admin action. Deleting somebody's territory
-- is irreversible and there is no undo, so it never happens on a single stray click.
local function confirm(text, onYes)
    local modal = ISModalDialog:new(0, 0, 360, 140, text, true, nil, function(_, button)
        if button.internal == "YES" then onYes() end
    end)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
end

-- Confirmation text for creating a no-claim zone, warning about what it will destroy.
-- The count comes from this client's copy of the registry, which for another faction's
-- claims can lag the server -- so it is phrased as a warning, not a promise. The server
-- recounts and reports what it actually removed.
local function noClaimConfirmText(rect)
    local hits = FF.claimsInNoClaim({ points = { rect } })
    local base = FF.text("UI_LFS_AdminBlockConfirm",
        "Block all faction claims in (%d,%d)-(%d,%d)?", rect[1], rect[2], rect[3], rect[4])
    if #hits == 0 then return base end
    return base .. FF.text("UI_LFS_AdminBlockRemoves",
        "\n\nThis will REMOVE %d claimed area(s) already inside it. That cannot be undone.", #hits)
end

-- Send adminClaimRect, asking first when it would destroy land the faction already has.
--
-- Both menu entries send WITHOUT `add`, and the server reads that as "replace the whole
-- claim set" -- so on a faction with several areas, one click silently deletes every
-- other one. The labels read additive. Confirm only when there is actually something to
-- lose, so the empty-faction dev loop stays a single click.
local function claimRectOrConfirm(name, x1, y1, x2, y2, after)
    local go = function()
        send("adminClaimRect", { name = name, x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
        if after then after() end
    end
    local f = FF.getFaction(name)
    local n = (f and f.claims) and #f.claims or 0
    if n <= 1 then return go() end
    confirm(FF.text("UI_LFS_AdminReplaceClaimConfirm",
        "Replace %s's claim with this one area?\n\nIts other %d area(s) will be removed. This cannot be undone.",
        name, n - 1), go)
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if not isLocalAdmin() then return end
    if test and ISWorldObjectContextMenu.Test then return true end

    local square
    for _, v in ipairs(worldobjects) do
        if v.getSquare then
            square = v:getSquare()
            if square then break end
        end
    end
    if not square then return end
    local x, y, z = square:getX(), square:getY(), square:getZ()

    local root = context:addOption(FF.tr("Faction Admin"))
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(root, sub)

    -- Whose land is this? Asked of the ZONE layer, not the registry, on purpose: an
    -- ORPHANED claim (one left behind by a faction that no longer exists) has no
    -- registry entry at all, and being able to clear those is half of why this exists.
    local ownerName = Claims and Claims.factionAt and Claims.factionAt(x, y) or nil
    if ownerName then
        local orphaned = FF.getFaction(ownerName) == nil
        local hereOpt = sub:addOption(FF.text("UI_LFS_AdminClaimHere",
            "Claim here: %s%s", ownerName, orphaned
                and FF.text("UI_LFS_AdminOrphanedSuffix", "  (orphaned - no such faction)") or ""))
        local hereSub = ISContextMenu:getNew(sub)
        sub:addSubMenu(hereOpt, hereSub)

        hereSub:addOption(FF.tr("Remove THIS area"), nil, function()
            confirm(FF.text("UI_LFS_AdminRemoveAreaConfirm",
                "Remove the claimed area at (%d,%d) from '%s'? This cannot be undone.",
                x, y, ownerName), function()
                send("adminRemoveClaimAt", { x = x, y = y })
            end)
        end)
        hereSub:addOption(FF.text("UI_LFS_AdminRemoveAllClaims", "Remove ALL claims of %s", ownerName), nil, function()
            confirm(FF.text("UI_LFS_AdminRemoveAllClaimsConfirm",
                "Remove EVERY claimed area belonging to '%s'? This cannot be undone.", ownerName),
                function()
                    send("adminRemoveClaimAt", { x = x, y = y, all = true })
                end)
        end)
    end

    -- No-claim zone under the cursor, if any: the one place an admin can see and clear
    -- one without knowing its id.
    local blockedBy = FF.noClaimAt(x, y)
    if blockedBy then
        local ncOpt = sub:addOption(FF.text("UI_LFS_AdminNoClaimHere",
            "No-claim zone here: %s", blockedBy))
        local ncSub = ISContextMenu:getNew(sub)
        sub:addSubMenu(ncOpt, ncSub)
        ncSub:addOption(FF.tr("Rename this zone..."), nil, function()
            local modal = ISTextBox:new(0, 0, 320, 160, FF.tr("Rename this no-claim zone:"),
                tostring(blockedBy), nil, function(target, button)
                    if button.internal ~= "OK" then return end
                    local nm = button.parent.entry:getInternalText()
                    if nm and nm ~= "" then
                        send("adminNoClaimRename", { x = x, y = y, name = nm })
                    end
                end)
            modal:initialise(); modal:addToUIManager()
            modal:setAlwaysOnTop(true); modal:bringToTop()
        end)

        if FF.adminState.cornerA then
            local a = FF.adminState.cornerA
            ncSub:addOption(FF.text("UI_LFS_AdminResizeCorners",
                "Resize to Corner A..B (A=%d,%d)", a.x, a.y),
                nil, function()
                    local rect = FF.normaliseRect({ a.x, a.y, x, y })
                    -- Same warning text as creating one: it counts the claims the new
                    -- area will destroy. Shrinking restores nothing, which the server
                    -- reply repeats.
                    confirm(noClaimConfirmText(rect), function()
                        send("adminNoClaimResize", { x = x, y = y,
                            x1 = rect[1], y1 = rect[2], x2 = rect[3], y2 = rect[4] })
                        FF.adminState.cornerA = nil
                    end)
                end)
        else
            local o = ncSub:addOption(FF.tr("Resize (place Corner A first)"))
            o.notAvailable = true
        end

        ncSub:addOption(FF.tr("Remove this no-claim zone"), nil, function()
            confirm(FF.text("UI_LFS_AdminStopBlockingConfirm",
                "Stop blocking claims in '%s'? Existing claims are not restored.", blockedBy),
                function()
                    send("adminNoClaimRemove", { x = x, y = y })
                end)
        end)
    end

    local active = FF.adminState.activeFaction

    -- Faction picker: choose the active faction straight from the menu (reads the
    -- replicated registry), so /ff admin use is optional.
    local pickLabel = active and FF.text("UI_LFS_AdminActiveFaction", "Active faction: %s", active)
        or FF.text("UI_LFS_AdminPickFaction", "Active faction: <none - pick one>")
    local pickOpt = sub:addOption(pickLabel)
    local pickSub = ISContextMenu:getNew(sub)
    sub:addSubMenu(pickOpt, pickSub)
    local any = false
    for name in pairs(FF.getData().factions or {}) do
        any = true
        pickSub:addOption((name == active and "* " or "") .. name, nil, function()
            FF.adminState.activeFaction = name
            output("Admin: active faction is now '" .. name .. "'.")
        end)
    end
    if not any then
        local o = pickSub:addOption(FF.text("UI_LFS_AdminNoFactions",
            "No factions yet - /ff admin create <name>"))
        o.notAvailable = true
    end

    if active then
        sub:addOption(FF.text("UI_LFS_AdminClaim20", "Claim 20x20 here -> %s", active), nil, function()
            local half = 10
            claimRectOrConfirm(active, x - half, y - half, x - half + 19, y - half + 19)
        end)
    else
        local o = sub:addOption(FF.text("UI_LFS_AdminClaimPickFirst",
            "Claim here (pick an active faction first)"))
        o.notAvailable = true
    end

    sub:addOption(FF.text("UI_LFS_AdminCornerA", "Corner A here (%d,%d)", x, y), nil, function()
        FF.adminState.cornerA = { x = x, y = y }
        output(string.format("Admin: corner A set at (%d,%d). Right-click the far corner for corner B.", x, y))
    end)

    if FF.adminState.cornerA then
        local a = FF.adminState.cornerA
        if active then
            sub:addOption(FF.text("UI_LFS_AdminCornerBClaim",
                "Corner B here -> claim %s (A=%d,%d)", active, a.x, a.y), nil, function()
                claimRectOrConfirm(active, a.x, a.y, x, y, function()
                    FF.adminState.cornerA = nil
                end)
            end)
        end
        sub:addOption(FF.text("UI_LFS_AdminCornerBBlock",
            "Corner B here -> BLOCK claims (A=%d,%d)", a.x, a.y), nil, function()
            local rect = FF.normaliseRect({ a.x, a.y, x, y })
            confirm(noClaimConfirmText(rect), function()
                send("adminNoClaimAdd", { x1 = rect[1], y1 = rect[2], x2 = rect[3], y2 = rect[4] })
                FF.adminState.cornerA = nil
            end)
        end)
        sub:addOption(FF.tr("Clear corner A"), nil, function()
            FF.adminState.cornerA = nil
            output("Admin: corner A cleared.")
        end)
    end

    if active then
        sub:addOption(FF.text("UI_LFS_AdminSetRespawn", "Set respawn here -> %s", active), nil, function()
            send("adminSetRespawn", { name = active, x = x, y = y, z = z })
        end)
    end

    sub:addOption(FF.tr("Teleport here"), nil, function()
        local p = getPlayer()
        if p and p.teleportTo then p:teleportTo(x + 0.5, y + 0.5, z) end
    end)

    -- Block claiming in a 20x20 box here. Named via a prompt;
    -- for a bigger or non-square area, use Corner A / Corner B.
    sub:addOption(FF.tr("Block claims here (20x20)..."), nil, function()
        local half = 10
        local rect = FF.normaliseRect({ x - half, y - half, x - half + 19, y - half + 19 })
        local modal = ISTextBox:new(0, 0, 320, 160, FF.tr("Name this no-claim zone:"), "", nil,
            function(target, button)
                if button.internal ~= "OK" then return end
                local nm = button.parent.entry:getInternalText()
                confirm(noClaimConfirmText(rect), function()
                    send("adminNoClaimAdd", { x1 = rect[1], y1 = rect[2], x2 = rect[3], y2 = rect[4], name = nm })
                end)
            end)
        modal:initialise(); modal:addToUIManager()
        modal:setAlwaysOnTop(true); modal:bringToTop()
    end)

    -- Force a relationship between the active faction and another (dev tool).
    if active then
        local relOpt = sub:addOption(FF.text("UI_LFS_AdminSetRelation", "Set relation: %s <-> ...", active))
        local relSub = ISContextMenu:getNew(sub)
        sub:addSubMenu(relOpt, relSub)
        local anyOther = false
        for name in pairs(FF.getData().factions or {}) do
            if name ~= active then
                anyOther = true
                local fOpt = relSub:addOption(name)
                local fSub = ISContextMenu:getNew(relSub)
                relSub:addSubMenu(fOpt, fSub)
                fSub:addOption(FF.tr("Ally"), nil, function() send("adminSetRelation", { a = active, b = name, status = "ally" }) end)
                fSub:addOption(FF.tr("Enemy"), nil, function() send("adminSetRelation", { a = active, b = name, status = "enemy" }) end)
                fSub:addOption(FF.tr("Neutral"), nil, function() send("adminSetRelation", { a = active, b = name, status = "neutral" }) end)
            end
        end
        if not anyOther then
            local o = relSub:addOption(FF.tr("No other factions yet"))
            o.notAvailable = true
        end
    end

    -- Faction settings + force-decay for the active faction (dev tools).
    if active then
        -- Faction settings an admin could not reach before: every setter is owner-gated
        -- for players, so an admin-created faction was stuck with its defaults until its
        -- owner logged in. Reaching them needs no active claim, just a picked faction.
        local facOpt = sub:addOption(FF.text("UI_LFS_AdminFactionMenu", "Faction: %s ...", active))
        local facSub = ISContextMenu:getNew(sub)
        sub:addSubMenu(facOpt, facSub)

        facSub:addOption(FF.tr("Rename..."), nil, function()
            local modal = ISTextBox:new(0, 0, 320, 160,
                FF.text("UI_LFS_AdminNewName", "New name for '%s':", active), active,
                nil, function(target, button)
                    if button.internal ~= "OK" then return end
                    local nm = button.parent.entry:getInternalText()
                    if not nm or nm == "" or nm == active then return end
                    confirm(FF.text("UI_LFS_AdminRenameConfirm",
                        "Rename '%s' to '%s'?\n\nEvery reference moves with it -- claims, wars, pacts and members.",
                        active, nm),
                        function()
                            send("adminRename", { name = active, newName = nm })
                            FF.adminState.activeFaction = nm   -- keep the menu pointing at it
                        end)
                end)
            modal:initialise(); modal:addToUIManager()
            modal:setAlwaysOnTop(true); modal:bringToTop()
        end)

        local facRec = FF.getFaction(active)
        local ownOpt = facSub:addOption(FF.tr("Transfer ownership ->"))
        local ownSub = ISContextMenu:getNew(facSub)
        facSub:addSubMenu(ownOpt, ownSub)
        local anyMember = false
        for user in pairs(facRec and facRec.members or {}) do
            if user ~= (facRec and facRec.owner) then
                anyMember = true
                ownSub:addOption(user, nil, function()
                    confirm(FF.text("UI_LFS_AdminOwnerConfirm",
                        "Make %s the owner of '%s'?\n\n%s becomes an ordinary member.",
                        user, active, tostring(facRec and facRec.owner)), function()
                        send("transferOwnership", { faction = active, username = user })
                    end)
                end)
            end
        end
        if not anyMember then
            local o = ownSub:addOption(FF.tr("No other members"))
            o.notAvailable = true
        end

        -- A player disbanding their OWN faction has always been modal-confirmed; an
        -- admin destroying somebody else's had nothing.
        sub:addOption(FF.text("UI_LFS_AdminForceDecay", "Force-decay (disband) %s", active), nil, function()
            confirm(FF.text("UI_LFS_AdminForceDecayConfirm",
                "Force-decay '%s'?\n\nThis permanently deletes its claims and roster, and dissolves its wars and pacts. This cannot be undone.", active), function()
                send("adminDecay", { name = active })
            end)
        end)
    end

    sub:addOption(FF.tr("List factions (console/chat)"), nil, function()
        send("adminList", {})
    end)
end

if FF._adminContextMenuHook then
    Events.OnFillWorldObjectContextMenu.Remove(FF._adminContextMenuHook)
end
FF._adminContextMenuHook = onFillWorldObjectContextMenu
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

print("[LFS] admin lua loaded")
