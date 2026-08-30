-- Lascivious Factions System - faction name tags (client side).
--
-- Two surfaces, both best-effort / advisory (the same trust tier as the permission
-- and friendly-fire hooks) and independently sandbox-gated:
--
--   1. Chat tags -- prefix each chat line with the sender's coloured [TAG] so you
--      can tell factions apart in general chat. PZ's ISChat bakes a line's text at
--      the moment ISChat.addLineInChat runs (it calls message:getTextWithPrefix()
--      immediately, not lazily), so we must mutate the ChatMessage BEFORE vanilla
--      handles it: we remove vanilla's OnAddMessage handler and re-add a wrapper
--      that tags the message and then calls the original. Gated by ShowFactionTagsInChat.
--
--   2. Overhead nameplates -- mirror the LFS roster into client-local native Faction
--      objects. The game then composes [TAG] and username in the same TextDrawObject,
--      with its own movement, distance and line-of-sight behaviour. Gated by
--      ShowNameplates (0 off / 1 own+allies+enemies / 2 all).
--
-- Faction membership for any username comes from the synced playerIndex
-- (FF.getFactionOfPlayer); tag/colour from FF.getFaction + UI.factionColor. The
-- server remains unaware of the native shadow objects and LFS remains authoritative.

require "LFS_Shared"
require "LFS_UI"

local FF = LasciviousFactionsSystem
local UI = FF.UI

if isServer() then return end

-- ---------------------------------------------------------------------------
-- 1. Chat faction tags
-- ---------------------------------------------------------------------------

-- Splice a faction-coloured [TAG] onto the LEFT of a chat line, in the chat panel
-- ONLY. We post-process the line ISChat just appended rather than editing the
-- ChatMessage text, so:
--   * the tag never leaks into the overhead speech bubble (that reads the message
--     text, which we leave untouched), and
--   * the colour actually works -- PZ escapes angle brackets inside message TEXT
--     (so an "<RGB>" spliced there renders literally), but a colour tag we splice
--     into the already-built line, outside the message text, is parsed normally by
--     ISRichTextPanel (which is what colours server/system lines).
-- <PUSHRGB>/<POPRGB> scope the colour to just the tag so the rest of the line keeps
-- its own colour. No-op for lines with no player author (radio/server/our notices).
local function prependFactionTag(message, tabID)
    if not FF.getOptions().showFactionTagsInChat then return end
    pcall(function()
        if not (message and message.getAuthor) then return end
        local author = message:getAuthor()
        if not author or author == "" then return end
        local fname = FF.getFactionOfPlayer(author)
        if not fname then return end
        local faction = FF.getFaction(fname)
        -- Also sanitize at render time so an old save created before the server-side
        -- validation cannot inject rich-text directives into chat.
        local tag = FF.truncateUtf8(
            tostring((faction and faction.tag) or fname):gsub("[%c<>]", ""), 24)
        local c = UI.factionColor(fname)

        local inst = ISChat.instance
        if not inst then return end
        -- Muted authors: vanilla addLineInChat returns without appending a line, so
        -- skip (otherwise we'd tag the previous, unrelated line).
        if inst.mutedUsers and inst.mutedUsers[author] then return end
        -- The tab ISChat.addLineInChat appended to (mirror its own tabID lookup).
        local tab
        for _, t in ipairs(inst.tabs or {}) do
            if t.tabID == tabID then tab = t break end
        end
        tab = tab or inst.chatText
        local lines = tab and tab.chatTextLines
        if not (lines and #lines > 0) then return end

        local idx = #lines
        if string.find(lines[idx], "PUSHRGB", 1, true) then return end   -- already tagged

        -- Capture whether the tab is pinned to the bottom BEFORE we re-paginate. Vanilla
        -- addLineInChat already scrolled to bottom for a normal new line, so this reads
        -- true unless the user had deliberately scrolled up. Our paginate() below would
        -- otherwise drop that scroll -- which is what killed auto-scroll once the mod's
        -- chat tags were enabled.
        local scrolledToBottom = (tab:getScrollHeight() <= tab:getHeight())
            or (tab.vscroll and tab.vscroll.pos == 1)

        local chunk = string.format(" <PUSHRGB:%.3f,%.3f,%.3f> [%s] <POPRGB> ", c.r, c.g, c.b, tag)
        lines[idx] = chunk .. lines[idx]

        -- Rebuild the tab text and re-paginate (mirrors addLineInChat's own tail).
        local newText = ""
        for i, v in ipairs(lines) do
            if i == #lines then v = string.gsub(v, " <LINE> $", "") end
            newText = newText .. v
        end
        tab.text = newText
        tab:paginate()

        -- Restore the bottom-pin paginate() just discarded (same call vanilla uses).
        if scrolledToBottom then tab:setYScroll(-10000) end
    end)
end

-- Run our tagger AFTER vanilla's chat renderer (which builds the line), then splice
-- the coloured tag into it. Done once at game start; we re-register vanilla's own
-- OnAddMessage handler behind ours so ordering is guaranteed.
local chatHookInstalled = false
local function installChatHook()
    if chatHookInstalled then return end
    if not (Events.OnAddMessage and ISChat and ISChat.addLineInChat) then return end
    chatHookInstalled = true
    local ok, err = pcall(function()
        local vanilla = ISChat.addLineInChat
        if FF._chatTagMessageHook then Events.OnAddMessage.Remove(FF._chatTagMessageHook) end
        Events.OnAddMessage.Remove(vanilla)
        local function taggedChatMessage(message, tabID)
            vanilla(message, tabID)
            prependFactionTag(message, tabID)
        end
        FF._chatTagMessageHook = taggedChatMessage
        Events.OnAddMessage.Add(taggedChatMessage)
    end)
    if not ok then
        FF.warn("chat tag hook failed: " .. tostring(err)
            .. " (chat tags disabled)")
    end
end
if FF._chatTagGameStartHook then Events.OnGameStart.Remove(FF._chatTagGameStartHook) end
FF._chatTagGameStartHook = installChatHook
Events.OnGameStart.Add(installChatHook)

-- ---------------------------------------------------------------------------
-- 2. Native overhead faction tags
-- ---------------------------------------------------------------------------

-- B42 does not draw the native tag merely because IsoPlayer.tagPrefix was filled.
-- IsoGameCharacter:updateUserName() asks Faction.getPlayerFaction(player) on every
-- rebuild and clears tagPrefix when that lookup fails. The old LFS implementation
-- therefore had to project and draw a second TextDrawObject on OnPostRender, which
-- could visibly trail the engine-owned username while a player moved.
--
-- Keep the LFS registry authoritative, but mirror its roster into client-local
-- "shadow" zombie.characters.Faction objects. We never send a vanilla faction
-- packet and the server never sees these objects. Their sole purpose is to let the
-- engine compose [TAG] and username into its ONE native TextDrawObject.

-- Hot reload from the old renderer: remove its OnPostRender callback immediately.
if Events.OnPostRender and FF._nameplateRender then
    Events.OnPostRender.Remove(FF._nameplateRender)
    FF._nameplateRender = nil
end

-- A previous copy of this adapter may still be installed after a Lua reload.
if FF._nativeNameplateTeardown then
    pcall(FF._nativeNameplateTeardown)
    FF._nativeNameplateTeardown = nil
end

local SHADOW_NAME_PREFIX = "__LFS_SHADOW__:"
local SHADOW_OWNER_PREFIX = "__LFS_OWNER__:"
local RECONCILE_INTERVAL = 1 -- seconds; roster changes also mark the adapter dirty

-- Kept on the shared namespace so a hot reload can remove exactly the Java objects
-- it created. We intentionally do not identify objects by name during cleanup: a
-- real vanilla faction with an unfortunate name must never be touched.
local shadows = FF._nativeNameplateShadows or {}
local originalShowTag = FF._nativeNameplateOriginalShowTag or {}
FF._nativeNameplateShadows = shadows
FF._nativeNameplateOriginalShowTag = originalShowTag

local hooks = {}
local dirty = true
local lastReconcile = 0
local lastMode = nil
local readyLogged = false
local warnedUnavailable = false
local warnedCollisions = {}

local function nameplateMode()
    local opts = FF.getOptions()
    return FF.nameplateMode and FF.nameplateMode() or (opts.showNameplates or 0)
end

local function factionList()
    if not (_G.Faction and Faction.getFactions) then return nil end
    return Faction.getFactions()
end

local function listContains(list, object)
    if not (list and object) then return false end
    for i = 0, list:size() - 1 do
        if list:get(i) == object then return true end
    end
    return false
end

local function listRemoveObject(list, object)
    if not (list and object) then return end
    -- Remove by index to avoid Kahlua choosing ArrayList.remove(Object)'s integer
    -- overload incorrectly.
    for i = list:size() - 1, 0, -1 do
        if list:get(i) == object then list:remove(i) end
    end
end

local function isManagedShadow(object)
    if not object then return false end
    for _, entry in pairs(shadows) do
        if entry.object == object then return true end
    end
    return false
end

local function restoreShowTag(username)
    local saved = originalShowTag[username]
    if not saved then return end
    originalShowTag[username] = nil
    if saved.player and saved.player.setShowTag then
        pcall(function() saved.player:setShowTag(saved.value == true) end)
    end
end

local function restoreAllShowTags()
    local names = {}
    for username in pairs(originalShowTag) do names[#names + 1] = username end
    for _, username in ipairs(names) do restoreShowTag(username) end
end

local function removeAllShadows()
    local list = factionList()
    if list then
        for _, entry in pairs(shadows) do
            listRemoveObject(list, entry.object)
        end
    end
    for name in pairs(shadows) do shadows[name] = nil end
    restoreAllShowTags()
end

local function newShadow(factionName)
    local list = factionList()
    if not list then return nil end
    local internalName = SHADOW_NAME_PREFIX .. tostring(factionName)
    -- The owner is deliberately a synthetic, impossible-in-normal-use username.
    -- Every actual LFS member, including the LFS owner, lives in getPlayers(). This
    -- makes ownership transfers a plain roster rebuild instead of requiring a new
    -- immutable native owner.
    local native = Faction.new(internalName, SHADOW_OWNER_PREFIX .. tostring(factionName))
    list:add(native)
    local entry = { object = native, internalName = internalName, colorKey = nil }
    shadows[factionName] = entry
    return entry
end

local function isHostile(myFaction, otherFaction)
    if not (myFaction and otherFaction) or myFaction == otherFaction then return false end
    if not FF.getOptions().showEnemyNameplates then return false end
    local mine = FF.getFaction(myFaction)
    return (mine and mine.relations and mine.relations[otherFaction] == "enemy")
        or FF.warBetween(myFaction, otherFaction)
end

local function updateShadowAppearance(myFaction)
    for factionName, entry in pairs(shadows) do
        local faction = FF.getFaction(factionName)
        if faction and entry.object then
            local tag = tostring((faction.tag and faction.tag ~= "") and faction.tag or factionName)
            if entry.tag ~= tag then
                entry.object:setTag(tag)
                entry.tag = tag
            end

            -- Enemy red is viewer-relative, so each client colours its own shadow
            -- registry. Other clients and the authoritative LFS data are unaffected.
            local c = isHostile(myFaction, factionName) and UI.color.bad
                or UI.factionColor(factionName)
            local colorKey = string.format("%.4f/%.4f/%.4f", c.r, c.g, c.b)
            if entry.colorKey ~= colorKey then
                entry.object:setTagColor(ColorInfo.new(c.r, c.g, c.b, 1))
                entry.colorKey = colorKey
            end
        end
    end
end

local function syncShadowRegistry()
    local list = factionList()
    if not list then error("zombie.characters.Faction is unavailable") end

    local data = FF.getData()

    -- Remove deleted factions, and re-add an object if the native client replaced
    -- its static faction list during a network refresh.
    for factionName, entry in pairs(shadows) do
        if not data.factions[factionName] then
            listRemoveObject(list, entry.object)
            shadows[factionName] = nil
        elseif not listContains(list, entry.object) then
            list:add(entry.object)
        end
    end

    for factionName in pairs(data.factions) do
        if not shadows[factionName] then newShadow(factionName) end
    end

    -- Clear all managed rosters first. That makes a join/leave/transfer atomic from
    -- this rebuild's point of view and prevents addPlayer()'s global duplicate scan
    -- from retaining stale memberships. We mutate the returned ArrayList directly;
    -- no vanilla sync method is called.
    for _, entry in pairs(shadows) do
        entry.object:getPlayers():clear()
    end

    for username, factionName in pairs(data.playerIndex or {}) do
        local entry = shadows[factionName]
        if entry and type(username) == "string" and username ~= "" then
            local existing = Faction.getPlayerFaction(username)
            if existing and not isManagedShadow(existing) then
                -- Preserve genuine vanilla state. This player cannot be placed in a
                -- shadow too because getPlayerFaction() returns only one faction.
                if not warnedCollisions[username] then
                    warnedCollisions[username] = true
                    FF.warn("native faction already owns player '"
                        .. username .. "'; LFS native name tag skipped for that player")
                end
            else
                entry.object:getPlayers():add(username)
                warnedCollisions[username] = nil
            end
        end
    end
end

local function eachWorldPlayer(fn)
    local players = getOnlinePlayers()
    local found = false
    if players and players.size then
        for i = 0, players:size() - 1 do
            local player = players:get(i)
            if player then found = true; fn(player) end
        end
    end
    -- In true singleplayer getOnlinePlayers() is a valid but empty ArrayList.
    if not found then
        for i = 0, 3 do
            local player = getSpecificPlayer(i)
            if player then fn(player) end
        end
    end
end

local function updatePlayerVisibility(mode, myFaction)
    local seen = {}
    eachWorldPlayer(function(player)
        local username = player:getUsername()
        if not username or username == "" then return end
        seen[username] = true

        local factionName = FF.getFactionOfPlayer(username)
        local entry = factionName and shadows[factionName]
        local nativeFaction = Faction.getPlayerFaction(player)
        if not (entry and nativeFaction == entry.object) then
            restoreShowTag(username)
            return
        end

        local saved = originalShowTag[username]
        if not saved or saved.player ~= player then
            -- Restore a replaced/streamed-out IsoPlayer before tracking its new Java
            -- object. This is local state only; no sendPlayerExtraInfo() is called.
            if saved then restoreShowTag(username) end
            originalShowTag[username] = {
                player = player,
                value = player:isShowTag(),
            }
        end

        local visible = mode >= 2
        if mode == 1 then
            visible = factionName == myFaction
                or (myFaction and FF.areAllied(factionName, myFaction))
                or isHostile(myFaction, factionName)
        end
        player:setShowTag(visible == true)
    end)

    -- Do not retain Java player objects after they leave the streamed player list.
    local gone = {}
    for username in pairs(originalShowTag) do
        if not seen[username] then gone[#gone + 1] = username end
    end
    for _, username in ipairs(gone) do restoreShowTag(username) end
end

local function shadowsStillInstalled()
    local list = factionList()
    if not list then return false end
    for _, entry in pairs(shadows) do
        if not listContains(list, entry.object) then return false end
    end
    return true
end

local function reconcile()
    local mode = nameplateMode()
    if mode ~= lastMode then
        dirty = true
        lastMode = mode
    end

    if mode <= 0 then
        -- Kahlua B42 does not expose Lua's global next().
        if not FF.isEmpty(shadows) or not FF.isEmpty(originalShowTag) then removeAllShadows() end
        dirty = false
        return
    end

    if not shadowsStillInstalled() then dirty = true end
    if dirty then
        syncShadowRegistry()
        dirty = false
    end

    local me = getPlayer()
    local myFaction = me and FF.getFactionOfPlayer(me:getUsername()) or nil
    updateShadowAppearance(myFaction)
    updatePlayerVisibility(mode, myFaction)

    if not readyLogged then
        readyLogged = true
        FF.print("native faction name-tag adapter ready; custom OnPostRender layer removed")
    end
end

local function reconcileTick()
    local now = getTimestamp()
    if not dirty and now - lastReconcile < RECONCILE_INTERVAL then return end
    lastReconcile = now
    local ok, err = pcall(reconcile)
    if not ok and not warnedUnavailable then
        warnedUnavailable = true
        FF.warn("native faction name-tag adapter failed: " .. tostring(err))
    elseif ok then
        warnedUnavailable = false
    end
end

local function markDirty()
    dirty = true
end

local function onReceiveGlobalModData(tableName)
    if tableName == FF.MODDATA then markDirty() end
end

local function onServerCommand(module, command)
    if module == FF.MODULE and command == "syncData" then markDirty() end
end

local function teardown()
    if Events.OnTick and hooks.tick then Events.OnTick.Remove(hooks.tick) end
    if Events.OnGameStart and hooks.gameStart then Events.OnGameStart.Remove(hooks.gameStart) end
    if Events.OnCreatePlayer and hooks.createPlayer then Events.OnCreatePlayer.Remove(hooks.createPlayer) end
    if Events.OnMiniScoreboardUpdate and hooks.scoreboard then
        Events.OnMiniScoreboardUpdate.Remove(hooks.scoreboard)
    end
    if Events.OnReceiveGlobalModData and hooks.modData then
        Events.OnReceiveGlobalModData.Remove(hooks.modData)
    end
    if Events.OnServerCommand and hooks.serverCommand then
        Events.OnServerCommand.Remove(hooks.serverCommand)
    end
    if Events.OnDisconnect and hooks.disconnect then Events.OnDisconnect.Remove(hooks.disconnect) end
    removeAllShadows()
end

hooks.tick = reconcileTick
hooks.gameStart = markDirty
hooks.createPlayer = markDirty
hooks.scoreboard = markDirty
hooks.modData = onReceiveGlobalModData
hooks.serverCommand = onServerCommand
hooks.disconnect = removeAllShadows

Events.OnTick.Add(hooks.tick)
Events.OnGameStart.Add(hooks.gameStart)
Events.OnCreatePlayer.Add(hooks.createPlayer)
if Events.OnMiniScoreboardUpdate then Events.OnMiniScoreboardUpdate.Add(hooks.scoreboard) end
Events.OnReceiveGlobalModData.Add(hooks.modData)
Events.OnServerCommand.Add(hooks.serverCommand)
if Events.OnDisconnect then Events.OnDisconnect.Add(hooks.disconnect) end

FF._nativeNameplateTeardown = teardown
