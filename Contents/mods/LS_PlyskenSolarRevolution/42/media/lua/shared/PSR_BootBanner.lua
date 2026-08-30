--[[
    PSR — BOOT BANNER
    ------------------------------------------------------------------------------
    Prints ONE line identifying this mod's build, at load time, in every process.

    WHY THIS EXISTS (2026-08-19). Two players posted a stack whose line numbers
    belonged to a build three versions old, and establishing that took reading the
    served files, the Steam API and the local Workshop cache. A player's report
    never carries its own version, so every one of them costs that archaeology.
    One line at boot makes every future report self-dating.

    It also prints WHERE the mod was loaded from. That is the half we could not
    measure at all: a manually installed copy sitting next to the Workshop one is
    invisible in a stack trace, and it pins a player to old files indefinitely.

    API (bytecode 42.20.3, verified — not inferred from names):
      · getModInfoByID(String) is a Lua global on LuaManager$GlobalObject and
        returns zombie.gameStates.ChooseGameInfo$Mod (null if unknown).
      · That class publicly exposes getModVersion() / getDir() / getSource() /
        getWorkshopID() / getId(). Vanilla itself calls getModVersion() at
        OptionScreens/ModSelector/ModInfoPanelParam.lua:23.

    WHY AT FILE LOAD AND NOT OnGameBoot: a top-level print in shared/ runs in
    EVERY process — solo, coop client, coop server, dedicated. That is the same
    placement that produced our measured isClient/isServer/isCoopHost table.
    ⚠️ CORRECTED 2026-08-19: an earlier version of this comment claimed a boot
    handler "never runs inside a server process". That is FALSE — `OnGameBoot`
    IS referenced by zombie/network/GameServer, so a dedicated server fires it.
    File-load placement is still the right choice (it needs no event at all, so
    it cannot be missed by an event that fires late or not at all), but the
    reason was wrong and a wrong reason travels further than a wrong line.

    KAHLUA: pcall does NOT catch Java RuntimeExceptions, so nothing here is
    wrapped in one — every call is guarded by presence instead. And the line is
    printed even when the lookup fails, otherwise silence would be ambiguous
    between "no banner shipped" and "banner ran and found nothing".
--]]

-- TAG is only the short label printed at the start of the line; MOD_ID is the
-- actual bundled id getModInfoByID() needs to find this mod's own info. They
-- used to be the same string ("PSR") before the pack's rename to
-- LS_PlyskenSolarRevolution, which is why this banner always printed vUNKNOWN.
local TAG = "PSR"
local MOD_ID = "LS_PlyskenSolarRevolution"

local function ctx()
    local c = isClient and isClient() or false
    local s = isServer and isServer() or false
    local h = isCoopHost and isCoopHost() or false
    return string.format("client=%s server=%s coop=%s", tostring(c), tostring(s), tostring(h))
end

local info = getModInfoByID and getModInfoByID(MOD_ID) or nil

if info then
    local ver = info.getModVersion and info:getModVersion() or "?"
    local src = info.getSource     and info:getSource()     or "?"
    -- 2026-08-19 : un mod charge depuis un dossier LOCAL n'a pas d'ID Workshop -- le getter rend
    -- une chaine VIDE, qui s'affichait comme un champ manquant, donc comme une panne. On le nomme.
    -- 🔑 C'est une information, pas une absence : `local` dit d'ou le mod a ete charge.
    local wid = info.getWorkshopID and info:getWorkshopID() or nil
    if wid == nil or wid == "" then wid = "local" end
    local dir = info.getDir        and info:getDir()        or "?"
    print(string.format("%s v%s | source=%s workshopID=%s | %s | dir=%s",
        TAG, tostring(ver), tostring(src), tostring(wid), ctx(), tostring(dir)))
else
    -- Not a crash: the identity lookup is unavailable, or the id is unknown here.
    -- Saying so is worth more than saying nothing.
    print(string.format("%s vUNKNOWN | getModInfoByID unavailable or id not found | %s", TAG, ctx()))
end
