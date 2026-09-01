-- LasciviousSystems - lossless SteamID64 resolution.
--
-- player:getSteamID() returns a Java `long`. Kahlua's Lua numbers are IEEE754
-- doubles with only 53 bits of exact integer precision; a SteamID64 (~7.6e16)
-- is well past that, so tostring(player:getSteamID()) silently rounds the
-- last 2-3 digits. Every account keyed by that string is keyed WRONG, and
-- nothing inside this mod ever notices on its own -- it's internally
-- consistent (every read and write rounds the same way) -- until something
-- OUTSIDE Lua (an HTTP bridge, a Discord bot) needs to match the exact,
-- correct SteamID64 and never can. See CLAUDE_SHOP_STEAMID_PRECISION_BUG.md.
--
-- The engine exposes getSteamIDFromUsername(username) -> String as a real
-- global Lua function (confirmed via javap on projectzomboid.jar's
-- LuaManager$GlobalObject.class -- it is a genuine engine global, not a
-- guess; LFS_API.lua already had a defensive "if getSteamIDFromUsername
-- then" call site for it before this file existed). That string comes
-- straight from the Java side and never passes through a Lua double, so it
-- is exact. Always resolve a SteamID through this file, never through
-- tostring(player:getSteamID()) directly.

LasciviousSystemsSteamId = LasciviousSystemsSteamId or {}
local M = LasciviousSystemsSteamId

local function log(message)
    print("[LasciviousSystems/SteamId] " .. tostring(message))
end

-- Format sanity, NOT a precision-loss detector -- a rounded double is still a
-- plausible-looking 17-digit number, this can't tell rounded from exact.
-- Digit-string + length check lifted from LFS_API.lua's own validSteamId(),
-- layered with the engine's isValidSteamID global when available.
function M.isValid(value)
    if type(value) ~= "string" then return nil end
    local text = value
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local prefixed = text:match("^[sS][tT][eE][aA][mM]:(%d+)$")
    if prefixed then text = prefixed end
    if text == "" or text == "0" or text == "nil" then return nil end
    if not string.match(text, "^%d+$") or #text < 15 or #text > 20 then return nil end
    if isValidSteamID then
        local ok, valid = pcall(isValidSteamID, text)
        if ok and valid == false then return nil end
    end
    return text
end

-- The exact SteamID64 for `player`, or nil. The only function anything
-- outside this file should use to build a NEW account key.
--
-- getSteamIDFromUsername() requires GameClient.client==true (confirmed via javap
-- on LuaManager$GlobalObject.class: it calls GameClient.instance:getPlayerFromUsername
-- and returns nil unless that guard passes) -- it is a CLIENT-ONLY engine global.
-- A true dedicated server process has no GameClient instance at all, so this call
-- is a GUARANTEED, PERMANENT no-op for every server-side caller there -- not a
-- transient failure worth a warning on every single resolve(). Short-circuit before
-- even trying, so this stays silent on a real dedicated server. Coop-host is a
-- single process acting as both client and server, so isClient() is true there and
-- the call can genuinely succeed; SP is handled by callers via isTrueSoloSP()/
-- SP_IDENTITY before this function is ever reached.
function M.resolve(player)
    if not player then return nil end
    if not isClient() then return nil end
    local okName, username = pcall(function() return player:getUsername() end)
    if okName and type(username) == "string" and username ~= "" and getSteamIDFromUsername then
        local ok, value = pcall(getSteamIDFromUsername, username)
        if ok then
            local valid = M.isValid(value)
            if valid then return valid end
        end
    end
    -- Do NOT fall back to player:getSteamID() for a new canonical identity:
    -- SteamID64 cannot round-trip through Kahlua's Lua number without losing
    -- precision. Reached here means isClient() was true but the lookup still
    -- failed (e.g. Steam mode off, or the username lookup itself came back
    -- empty) -- that IS worth a warning, unlike the dedicated-server case above.
    log("getSteamIDFromUsername unavailable/failed for a connected player -- refusing lossy getSteamID() fallback")
    return nil
end

-- Em singleplayer puro (nem cliente nem servidor) a engine nao expoe NENHUMA
-- identidade estavel derivavel do player object: getSteamIDFromUsername()
-- exige GameClient.client==true (so existe em MP real -- confirmado via
-- decompilacao de LuaManager$GlobalObject.getSteamIDFromUsername no
-- projectzomboid.jar) e o campo cru getSteamID() so e escrito por codigo de
-- rede (ConnectedPacket/CreatePlayerPacket/GameServer), entao em SP puro fica
-- 0 (invalido, M.isValid rejeita) a sessao inteira. E getUsername() TAMBEM
-- nao e estavel em SP: IsoPlayer.updateUsername() -- que so roda quando
-- !GameClient.client && !GameServer.server -- sobrescreve o campo com
-- getDescriptor():getForename()..getSurname() do PERSONAGEM ATUAL, trocando a
-- cada morte/personagem novo por design. Ou seja, em SP puro nao existe
-- NENHUMA identidade derivavel do player object -- mas so existe UM jogador
-- real por save, entao a chave certa e uma constante fixa, nunca derivada.
M.SP_IDENTITY = "sp:local-save"

function M.isTrueSoloSP()
    return not isClient() and not isServer()
end

function M.accountKey(player)
    if M.isTrueSoloSP() then return M.SP_IDENTITY end
    local steamId = M.resolve(player)
    return steamId and ("steam:" .. steamId) or nil
end

-- Reproduces the OLD bug's exact computation (tostring(player:getSteamID())),
-- for the SOLE purpose of finding data written under that wrong key before
-- this fix existed, so callers can migrate it forward. `correctKey` is the
-- caller's already-resolved M.accountKey(player) -- passed in so this doesn't
-- redundantly re-resolve it. Returns nil when there's nothing to migrate
-- (no SteamID, or the legacy computation happens to already match).
--
-- Safe to merge steam:<legacy> into steam:<correct> here specifically because
-- both are computed from the SAME live player object in the SAME call --
-- this is one player's own historical data under their own old wrong key,
-- never another player's account (unlike a username-based match, which
-- callers must NOT auto-merge -- see LasciviousShop_Server.lua's
-- mergeFallbackAccount comment on username reuse).
function M.legacyAccountKey(player, correctKey)
    if not player then return nil end
    local ok, steamId = pcall(function() return player:getSteamID() end)
    if not ok or steamId == nil then return nil end
    local legacy = tostring(steamId)
    if legacy == "" or legacy == "0" then return nil end
    local legacyKey = "steam:" .. legacy
    if legacyKey == correctKey then return nil end
    return legacyKey
end

return M
