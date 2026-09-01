-- HWNetBridge: bridge server-side simples entre o PZ e o bot Discord (Node.js),
-- via arquivos locais em ~/Zomboid/Lua/. Sem registro em Mods=, sem exigir nada do cliente.
--
-- Protocolo (nomes de arquivo fixos, sem listagem de diretorio):
--   hwbridge_heartbeat.json     escrito por nos a cada tick          (nos -> bot)
--   hwbridge_inbox.json         escrito pelo bot quando quer mandar um comando (bot -> nos)
--   hwbridge_outbox_result.json escrito por nos em resposta a um comando   (nos -> bot)
--   hwbridge_players.json       snapshot dos jogadores online a cada tick  (nos -> bot)
--   hwbridge_events.json        ring buffer dos ultimos eventos (mortes de personagem) (nos -> bot)
--   hwbridge_factions.json      snapshot basico das faccoes (LFS) a cada tick (nos -> bot)
--
-- Events.OnTick nao dispara em servidor headless (parece ligado ao render loop, que
-- nao existe sem cliente). Usamos Events.OnServerStarted para publicar o primeiro
-- snapshot e Events.EveryOneMinute para manter os arquivos atualizados depois.
--
-- Conectar/desconectar NAO e mais detectado aqui (era, ate 2026-08-12) -- esse tick
-- congela junto com o mundo quando o servidor fica vazio (PauseEmpty), entao perdiamos
-- eventos e ate misatribuiamos desconexoes ao jogador errado. Isso agora e feito no lado
-- do bot via A2S/Steam Query, que funciona mesmo com o mundo pausado.
--
-- Comandos aceitos no inbox (campo "type"): "ping", "grant_discord_reward" (credita
-- bonus de verificacao Discord na Lascivious Shop, ver LasciviousShop.grantExternalRewardOnce),
-- "bind_pz_identity" (so registra o vinculo verificado username<->steam:<id> na
-- Identity V2 -- NAO credita nada; existe porque getSteamIDFromUsername() exige
-- GameClient.client==true (confirmado via javap em LuaManager$GlobalObject) e por
-- isso NUNCA funciona a partir de Lua server-side num dedicated de verdade -- o bot
-- e a unica fonte de SteamID exato pra esses jogadores), e "admin_lua_exec" (executor
-- Lua administrativo generico, ver HWNetBridge_Admin_Lua_Exec.md). So um comando em
-- voo por vez -- o lado Node so pode escrever um novo comando depois de ler o
-- resultado do anterior.

local okSteamIdModule, SteamIdModule = pcall(require, "LasciviousSystems_SteamId")
local SteamId = okSteamIdModule and SteamIdModule or LasciviousSystemsSteamId
local okIdentityModule, IdentityModule = pcall(require, "LasciviousSystems_Identity")
local Identity = okIdentityModule and IdentityModule or LasciviousSystemsIdentity

local tickCounter = 0
local lastProcessedId = nil
local previousAlive = {}
local eventSeq = 0
local recentEvents = {}
local MAX_EVENTS = 20

-- admin_lua_exec: generic escape-hatch Lua executor for maintenance/diagnosis
-- from outside the server process (Discord bot's internal admin ops, a VPS
-- CLI, Claude/Codex operating the server). See HWNetBridge_Admin_Lua_Exec.md
-- for the full design. Always on -- explicit request, no enable/disable flag.
-- This is equivalent to a remote Lua console inside the running server: the
-- only real security boundary is "who can write to hwbridge_inbox.json on
-- this machine" (this bridge is pure local-file IPC, never a network port --
-- same boundary every other bridge command already relies on). Per the
-- design doc, do NOT try to blacklist keywords/APIs -- that is a false sense
-- of security a real admin console should not pretend to have.
--
-- Emergency kill switch (no code edit/restart needed): write ANY non-empty
-- content to hwbridge_disable_admin_lua in this same directory and every
-- request is refused immediately.
local ADMIN_LUA_DISABLE_SENTINEL = "hwbridge_disable_admin_lua"
local MAX_ADMIN_LUA_CODE_BYTES = 16384
local MAX_ADMIN_LUA_SERIALIZE_DEPTH = 6
local MAX_ADMIN_LUA_SERIALIZE_ITEMS = 500

local function jsonEscape(str)
    str = tostring(str or "")
    str = str:gsub('\\', '\\\\')
    str = str:gsub('"', '\\"')
    return str
end

local function jsonBool(value)
    return value == true and "true" or "false"
end

local function jsonNumber(value)
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then return "null" end
    return tostring(n)
end

local function jsonString(content, key)
    if type(content) ~= "string" or type(key) ~= "string" then return nil end
    local value = content:match('"' .. key .. '"%s*:%s*"([^"]*)"')
    if not value then value = content:match('"' .. key .. '"%s*:%s*(%d+)') end
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end

local function jsonQuotedString(content, key)
    if type(content) ~= "string" or type(key) ~= "string" then return nil end
    local value = content:match('"' .. key .. '"%s*:%s*"([^"]*)"')
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end

-- Every other jsonXxx(content, key) helper in this file stops at the first
-- raw '"', which is fine for the simple values (steamId, username, UUIDs)
-- every other command exchanges. admin_lua_exec's "code" field is arbitrary
-- Lua source and will routinely contain embedded quotes/newlines
-- (getPlayerFromUsername("Dahaka")), so it needs a real escape-aware
-- extractor. Handles the standard JSON escapes; \uXXXX is best-effort ASCII
-- only (returns nil / drops the codepoint above U+007F rather than
-- mis-decoding -- this bridge has no UTF-8 encoder and refusing beats
-- silently corrupting the script).
local function jsonEscapedString(content, key)
    if type(content) ~= "string" or type(key) ~= "string" then return nil end
    local _, afterKey = content:find('"' .. key .. '"%s*:%s*"')
    if not afterKey then return nil end
    local len = #content
    local out, i = {}, afterKey + 1
    while i <= len do
        local c = content:sub(i, i)
        if c == '"' then
            return table.concat(out)
        elseif c == "\\" then
            local nextc = content:sub(i + 1, i + 1)
            if nextc == "n" then out[#out + 1] = "\n"
            elseif nextc == "t" then out[#out + 1] = "\t"
            elseif nextc == "r" then out[#out + 1] = "\r"
            elseif nextc == "b" then out[#out + 1] = "\b"
            elseif nextc == "f" then out[#out + 1] = "\f"
            elseif nextc == '"' then out[#out + 1] = '"'
            elseif nextc == "\\" then out[#out + 1] = "\\"
            elseif nextc == "/" then out[#out + 1] = "/"
            elseif nextc == "u" then
                local hex = content:sub(i + 2, i + 5)
                local codepoint = tonumber(hex, 16)
                if codepoint and codepoint < 128 then out[#out + 1] = string.char(codepoint) end
                i = i + 4
            else
                out[#out + 1] = nextc
            end
            i = i + 2
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return nil -- unterminated string
end

local function jsonNumberString(content, key)
    if type(content) ~= "string" or type(key) ~= "string" then return nil end
    return content:match('"' .. key .. '"%s*:%s*(%d+)')
end

local function hasNumericSteamId(content)
    return jsonNumberString(content, "steamId")
        or jsonNumberString(content, "steamID64")
        or jsonNumberString(content, "steamID")
        or jsonNumberString(content, "steam_id_64")
        or jsonNumberString(content, "steam_id")
        or jsonNumberString(content, "steam64")
        or jsonNumberString(content, "steam")
        or jsonNumberString(content, "steamid")
end

local function validSteamId(value)
    if SteamId and type(SteamId.isValid) == "function" then
        return SteamId.isValid(value)
    end
    if type(value) ~= "string" then return nil end
    local text = value:gsub("^%s+", ""):gsub("%s+$", "")
    local prefixed = text:match("^[sS][tT][eE][aA][mM]:(%d+)$")
    if prefixed then text = prefixed end
    if text == "" or text == "0" then return nil end
    if not text:match("^%d+$") or #text < 15 or #text > 20 then return nil end
    return text
end

local function steamIdForUsername(username)
    if type(username) ~= "string" or username == "" or not getSteamIDFromUsername then return nil end
    local ok, value = pcall(getSteamIDFromUsername, username)
    return ok and validSteamId(value) or nil
end

local function writeFile(filename, content)
    local writer = getFileWriter(filename, true, false)
    if not writer then
        print("[HWNetBridge] ERRO: getFileWriter retornou nil para " .. filename)
        return false
    end
    writer:write(content)
    writer:close()
    return true
end

local function readFile(filename)
    local reader = getFileReader(filename, true)
    if not reader then return "" end

    local content = ""
    local line = reader:readLine()
    while line ~= nil do
        content = content .. line
        line = reader:readLine()
    end
    reader:close()
    return content
end

local function writeHeartbeat()
    tickCounter = tickCounter + 1

    local playerCount = 0
    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        playerCount = players:size()
    end

    local worldAgeHours = 0
    local okAge, age = pcall(function() return getGameTime():getWorldAgeHours() end)
    if okAge and age then
        worldAgeHours = age
    end

    local json = string.format(
        '{"type":"heartbeat","serverTime":%d,"tick":%d,"players":%d,"worldAgeHours":%.2f}',
        getTimestamp(), tickCounter, playerCount, worldAgeHours
    )
    writeFile("hwbridge_heartbeat.json", json)
end

-- Credita o bonus de verificacao Discord na Lascivious Shop. O Bridge valida apenas
-- identidade/transporte; valor, idempotencia e prova financeira ficam dentro da Shop.
local function grantDiscordVerificationReward(steamId, username, commandId, businessKey, usernameSource)
    if steamId == nil or steamId == "" then
        return false, "missing_steam_id"
    end
    local normalizedSteamId = validSteamId(steamId)
    if not normalizedSteamId then
        return false, "invalid_steam_id"
    end

    if not LasciviousShop then
        return false, "shop_api_unavailable"
    end

    local identity = { steamId = normalizedSteamId }
    identity.source = usernameSource or "discord_reward_bridge"
    identity.businessKey = businessKey or commandId
    if type(username) == "string" and username ~= "" then
        identity.username = username
        identity.usernameSource = usernameSource or "bridge_command"
    end

    if type(LasciviousShop.grantExternalRewardOnce) == "function" then
        return LasciviousShop.grantExternalRewardOnce(identity, "discord_verification", businessKey or commandId)
    end
    return false, "shop_api_unavailable"
end

-- Registers a verified username<->steam:<id> binding in Identity V2. Credits
-- nothing -- this exists purely because server-side Lua can never resolve a
-- connected player's own SteamID by itself on a real dedicated server (see the
-- header comment), so the bot is the only source of an exact SteamID for those
-- players until they show up in a grant. Safe to call repeatedly; a binding
-- that already matches is a no-op, a genuine conflict (this username already
-- verified-bound to a DIFFERENT steamId) is reported, never silently merged.
local function bindPzIdentity(steamId, username, usernameSource)
    if type(username) ~= "string" or username == "" then
        return false, "missing_username"
    end
    local normalizedSteamId = validSteamId(steamId)
    if not normalizedSteamId then
        return false, "invalid_steam_id"
    end
    if not (Identity and type(Identity.registerVerifiedBinding) == "function") then
        return false, "identity_module_unavailable"
    end
    local ok, err, steamKey = Identity.registerVerifiedBinding(
        username, normalizedSteamId, usernameSource or "bridge_bind_pz_identity")
    if not ok then
        return false, err or "identity_conflict", { accountKey = steamKey, username = username }
    end
    return true, nil, { accountKey = steamKey, username = username }
end

-- True when `t` is empty or has a contiguous 1..n integer key run (i.e. what
-- Lua's own #t / ipairs() convention treats as "an array"). Anything else --
-- a mix of string keys, a sparse integer sequence -- serializes as a JSON
-- object instead. Never trust this on a Java-backed value; every call site
-- wraps it in pcall.
local function isArrayLikeTable(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n == 0 then return true, 0 end
    for i = 1, n do
        if t[i] == nil then return false, n end
    end
    return true, n
end

-- Converts an admin_lua_exec return value to a JSON fragment. Only nil,
-- boolean, number, string and "plain" tables (recursively) are ever walked --
-- per the design doc, a function/userdata/Java-backed object (IsoPlayer,
-- getOnlinePlayers(), ...) must never be walked recursively, so it becomes a
-- safe `"<type>"` placeholder instead of a crash or an unbounded Java object
-- dump. Kahlua exposes Java objects to Lua as tables with method-call
-- metatables, so `type(value) == "table"` alone can't tell a plain Lua table
-- from one of those -- every table walk below is pcall-wrapped so an
-- unexpected iteration failure degrades to a placeholder instead of taking
-- the whole response down. `budget` is a shared {count=N} across the whole
-- call tree so a pathological/huge table is capped once, not per-branch.
local function serializeAdminLuaValue(value, depth, budget)
    depth = depth or 0
    budget.count = budget.count + 1
    if budget.count > MAX_ADMIN_LUA_SERIALIZE_ITEMS then return '"<truncated:too_many_items>"' end

    local vtype = type(value)
    if value == nil then return "null" end
    if vtype == "boolean" then return jsonBool(value) end
    if vtype == "number" then return jsonNumber(value) end
    if vtype == "string" then return '"' .. jsonEscape(value) .. '"' end
    if vtype ~= "table" then return '"<' .. jsonEscape(vtype) .. '>"' end
    if depth >= MAX_ADMIN_LUA_SERIALIZE_DEPTH then return '"<truncated:max_depth>"' end

    local okScan, isArray, count = pcall(isArrayLikeTable, value)
    if not okScan then return '"<unserializable_table>"' end

    local parts = {}
    if isArray then
        local okIter = pcall(function()
            for i = 1, count do
                parts[#parts + 1] = serializeAdminLuaValue(value[i], depth + 1, budget)
                if budget.count > MAX_ADMIN_LUA_SERIALIZE_ITEMS then break end
            end
        end)
        if not okIter then return '"<unserializable_table>"' end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local okIter = pcall(function()
        for k, v in pairs(value) do
            if type(k) == "string" or type(k) == "number" then
                parts[#parts + 1] = '"' .. jsonEscape(tostring(k)) .. '":' .. serializeAdminLuaValue(v, depth + 1, budget)
            end
            if budget.count > MAX_ADMIN_LUA_SERIALIZE_ITEMS then break end
        end
    end)
    if not okIter then return '"<unserializable_table>"' end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function adminLuaNowMs()
    if getTimestampMs then return getTimestampMs() end
    return math.floor((getTimestamp() or 0) * 1000)
end

-- Runs `code` as a full Lua chunk inside the server's own Lua state and
-- returns ok, errorReason, info. info.results holds every value the chunk
-- returned (info.result is just results[1], for callers that only care about
-- one value); on failure info.errorMessage/info.traceback are set (identical
-- strings if this Kahlua build's debug library doesn't expose traceback()).
--
-- NOT SAFE AGAINST NON-TERMINATING CODE: Kahlua's loadstring() has no
-- instruction limit or preemption (confirmed by this exact codebase --
-- PhunZones/client/PhunZones/ui/ui_editor.lua's own comment on this same
-- primitive). `while true do end` WILL hang the server's main Lua thread with
-- no way for this file to interrupt it. There is no safe fix for that from
-- pure Lua; the only mitigation is "don't run code you don't trust" and the
-- hwbridge_disable_admin_lua emergency sentinel checked below.
local function executeAdminLua(code, requestId, source)
    if readFile(ADMIN_LUA_DISABLE_SENTINEL) ~= "" then return false, "admin_lua_disabled" end
    if type(code) ~= "string" or code == "" then return false, "missing_code" end
    if #code > MAX_ADMIN_LUA_CODE_BYTES then return false, "code_too_large" end

    local startedAt = adminLuaNowMs()
    local chunk, compileErr = loadstring(code)
    if not chunk then
        local elapsed = adminLuaNowMs() - startedAt
        print(string.format(
            "[HWNetBridge/AdminLua] requestId=%s source=%s success=false stage=compile size=%d executionTimeMs=%d preview=%s",
            tostring(requestId), tostring(source), #code, elapsed, code:sub(1, 200)))
        return false, "compile_error", { errorMessage = tostring(compileErr), executionTimeMs = elapsed }
    end

    local hasTraceback = type(debug) == "table" and type(debug.traceback) == "function"
    local xres = { xpcall(chunk, hasTraceback and debug.traceback or tostring) }
    local ok = xres[1]
    table.remove(xres, 1)
    local elapsed = adminLuaNowMs() - startedAt

    print(string.format(
        "[HWNetBridge/AdminLua] requestId=%s source=%s success=%s size=%d executionTimeMs=%d preview=%s",
        tostring(requestId), tostring(source), tostring(ok), #code, elapsed, code:sub(1, 200)))

    if not ok then
        local errText = tostring(xres[1])
        return false, "lua_error", { errorMessage = errText, traceback = errText, executionTimeMs = elapsed }
    end
    return true, nil, { results = xres, result = xres[1], executionTimeMs = elapsed }
end

-- Only these three account-transaction statuses represent a proven, committed
-- ledger change (see LasciviousShop_Server.lua's grantExternalRewardOnce state
-- machine). Everything else -- processing (which no longer exists as a
-- terminal state), legacy_unproven, identity_conflict, integrity_conflict,
-- recipient_balance_limit, invalid_* -- must read as failure/retry to the bot,
-- never as "already paid".
local EXTERNAL_REWARD_SUCCESS_STATUS = {
    applied = true,
    already_committed = true,
    repaired = true,
}

local function processInbox()
    local content = readFile("hwbridge_inbox.json")
    if content == "" then return end

    local id = content:match('"id"%s*:%s*"([^"]+)"')
    local ctype = content:match('"type"%s*:%s*"([^"]+)"')

    if not id or id == lastProcessedId then return end
    lastProcessedId = id

    print("[HWNetBridge] Comando recebido: id=" .. tostring(id) .. " type=" .. tostring(ctype))

    -- admin_lua_exec's response shape (a possibly-nested `result`/`results`
    -- value, of arbitrary Lua type) doesn't fit the flat reward/bind template
    -- every other command shares below, so it builds and writes its own
    -- response and returns here instead of falling through.
    if ctype == "admin_lua_exec" then
        local code = jsonEscapedString(content, "code")
        local source = jsonQuotedString(content, "source") or "unknown"
        local ok, err, info = executeAdminLua(code, id, source)

        local budget = { count = 0 }
        local resultJson, resultsJson = "null", "[]"
        local errorMessage, tracebackText = "", ""
        local executionTimeMs = (info and info.executionTimeMs) or 0
        if ok then
            resultJson = serializeAdminLuaValue(info.result, 0, budget)
            local parts = {}
            for _, v in ipairs(info.results or {}) do
                parts[#parts + 1] = serializeAdminLuaValue(v, 0, budget)
            end
            resultsJson = "[" .. table.concat(parts, ",") .. "]"
        else
            errorMessage = (info and info.errorMessage) or tostring(err)
            tracebackText = (info and info.traceback) or errorMessage
        end

        local adminResultJson = string.format(
            '{"type":"command_result","id":"%s","success":%s,"status":"%s",' ..
            '"result":%s,"results":%s,"error":"%s","traceback":"%s","executionTimeMs":%s}',
            id, jsonBool(ok == true), jsonEscape(ok and "executed" or tostring(err)),
            resultJson, resultsJson, jsonEscape(errorMessage), jsonEscape(tracebackText),
            jsonNumber(executionTimeMs)
        )
        writeFile("hwbridge_outbox_result.json", adminResultJson)
        print("[HWNetBridge] Respondido (admin_lua_exec): id=" .. tostring(id)
            .. " success=" .. tostring(ok == true))
        return
    end

    local success = false
    local status = "unknown_command_type"
    local accountKey = ""
    local rewardUsername = ""
    local transactionKey = ""
    local amount, balanceBefore, balanceAfter = nil, nil, nil
    local ledgerCommitted, receiptCommitted = false, false
    local identitySource, uiPush = "", ""

    if ctype == "ping" then
        success = true
        status = "pong"
    elseif ctype == "grant_discord_reward" then
        local steamId = jsonQuotedString(content, "steamId")
            or jsonQuotedString(content, "steamID64")
            or jsonQuotedString(content, "steamID")
            or jsonQuotedString(content, "steam_id_64")
            or jsonQuotedString(content, "steam_id")
            or jsonQuotedString(content, "steam64")
            or jsonQuotedString(content, "steam")
            or jsonQuotedString(content, "steamid")
        local username = jsonString(content, "username")
            or jsonString(content, "pzUsername")
            or jsonString(content, "player")
            or jsonString(content, "playerName")
        local businessKey = jsonQuotedString(content, "businessKey")
        local usernameSource = jsonQuotedString(content, "usernameSource")

        local ok, err, info
        if not steamId and hasNumericSteamId(content) then
            ok, err = false, "invalid_steam_id_type"
        else
            ok, err, info = grantDiscordVerificationReward(steamId, username, id, businessKey, usernameSource)
        end

        status = (info and info.status) or (not ok and tostring(err)) or "applied"
        success = ok == true and EXTERNAL_REWARD_SUCCESS_STATUS[status] == true
            and info ~= nil and info.ledgerCommitted == true
        accountKey = (info and info.accountKey) or ""
        rewardUsername = (info and info.username) or username or ""
        transactionKey = (info and info.transactionKey) or ""
        amount = info and info.amount or nil
        balanceBefore = info and info.balanceBefore or nil
        balanceAfter = info and info.balanceAfter or nil
        ledgerCommitted = info ~= nil and info.ledgerCommitted == true
        receiptCommitted = info ~= nil and info.receiptCommitted == true
        identitySource = (info and info.identitySource) or ""
        uiPush = (info and info.uiPush) or ""
    elseif ctype == "bind_pz_identity" then
        local steamId = jsonQuotedString(content, "steamId")
            or jsonQuotedString(content, "steamID64")
            or jsonQuotedString(content, "steamID")
            or jsonQuotedString(content, "steam_id_64")
            or jsonQuotedString(content, "steam_id")
            or jsonQuotedString(content, "steam64")
            or jsonQuotedString(content, "steam")
            or jsonQuotedString(content, "steamid")
        local username = jsonString(content, "username")
            or jsonString(content, "pzUsername")
            or jsonString(content, "player")
            or jsonString(content, "playerName")
        local usernameSource = jsonQuotedString(content, "usernameSource")

        local ok, err, info
        if not steamId and hasNumericSteamId(content) then
            ok, err = false, "invalid_steam_id_type"
        else
            ok, err, info = bindPzIdentity(steamId, username, usernameSource)
        end

        status = ok and "bound" or (tostring(err) or "bind_failed")
        success = ok == true
        accountKey = (info and info.accountKey) or ""
        rewardUsername = (info and info.username) or username or ""
    end

    local resultJson = string.format(
        '{"type":"command_result","id":"%s","success":%s,"status":"%s","message":"%s",' ..
        '"accountKey":"%s","username":"%s","transactionKey":"%s","amount":%s,' ..
        '"balanceBefore":%s,"balanceAfter":%s,"ledgerCommitted":%s,"receiptCommitted":%s,' ..
        '"identitySource":"%s","uiPush":"%s"}',
        id, jsonBool(success), jsonEscape(status), jsonEscape(status),
        jsonEscape(accountKey), jsonEscape(rewardUsername), jsonEscape(transactionKey), jsonNumber(amount),
        jsonNumber(balanceBefore), jsonNumber(balanceAfter), jsonBool(ledgerCommitted), jsonBool(receiptCommitted),
        jsonEscape(identitySource), jsonEscape(uiPush)
    )
    writeFile("hwbridge_outbox_result.json", resultJson)
    print("[HWNetBridge] Respondido: " .. resultJson)
end

local function pushEvent(eventType, username, extra)
    eventSeq = eventSeq + 1

    local event = {
        seq = eventSeq,
        type = eventType,
        username = username,
        timestamp = getTimestamp()
    }
    if extra then
        event.hoursSurvived = extra.hoursSurvived
        event.zombieKills = extra.zombieKills
    end

    table.insert(recentEvents, event)
    while #recentEvents > MAX_EVENTS do
        table.remove(recentEvents, 1)
    end
end

local function writeEvents()
    if #recentEvents == 0 then return end

    local parts = {}
    for _, e in ipairs(recentEvents) do
        local extraJson = ""
        if e.hoursSurvived ~= nil then
            extraJson = string.format(',"hoursSurvived":%.2f,"zombieKills":%d', e.hoursSurvived, e.zombieKills or 0)
        end

        table.insert(parts, string.format(
            '{"seq":%d,"type":"%s","username":"%s","timestamp":%d%s}',
            e.seq, e.type, jsonEscape(e.username), e.timestamp, extraJson
        ))
    end
    writeFile("hwbridge_events.json", "[" .. table.concat(parts, ",") .. "]")
end

-- So entram no snapshot (e no leaderboard) personagens vivos. A transicao vivo -> morto
-- e detectada aqui e vira um evento "player_died" (com as estatisticas finais).
--
-- NAO detectamos mais conectar/desconectar aqui (removido em 2026-08-12): esse tick so
-- roda em Events.EveryOneMinute, que fica CONGELADO quando o mundo fica vazio e pausado
-- (PauseEmpty) -- isso fazia o ultimo jogador sumir "silenciosamente" (sem log) e, pior,
-- o proximo jogador a conectar acabava disparando um "desconectou" com o nome de quem
-- ja tinha saido antes, porque o diff so rodava de novo quando o tick voltava a existir.
-- Deteccao de conectar/desconectar agora e feita no lado do bot via A2S (Steam Query),
-- que responde mesmo com o mundo pausado -- ver pzbridge/lib/presencePoller.js.
local function collectPlayersAndDetectDeaths()
    local snapshot = {}
    local currentAlive = {}

    local ok, players = pcall(getOnlinePlayers)
    if ok and players then
        local count = players:size() - 1
        for i = 0, count do
            local playerObj = players:get(i)
            if playerObj then
                local username = playerObj:getUsername()
                local steamId = steamIdForUsername(username)

                if playerObj:isDead() then
                    if previousAlive[username] then
                        pushEvent("player_died", username, {
                            hoursSurvived = playerObj:getHoursSurvived(),
                            zombieKills = playerObj:getZombieKills()
                        })
                    end
                else
                    currentAlive[username] = true
                    table.insert(snapshot, string.format(
                        '{"username":"%s","steamId":"%s","accountKey":"%s","hoursSurvived":%.2f,"zombieKills":%d}',
                        jsonEscape(username), jsonEscape(steamId or ""), jsonEscape(steamId and ("steam:" .. steamId) or ""),
                        playerObj:getHoursSurvived(), playerObj:getZombieKills()
                    ))
                end
            end
        end
    end

    previousAlive = currentAlive
    writeFile("hwbridge_players.json", "[" .. table.concat(snapshot, ",") .. "]")
end

-- Integracao opcional com o Lascivious Factions System (LFS), se o mod estiver instalado.
-- O require() so pode ser feito depois que todos os mods carregaram (por isso e chamado
-- de dentro do tick, nunca no topo do arquivo -- ver Faccao_README.md do mod). Tenta de
-- novo a cada tick ate conseguir, depois fica em cache pro resto da sessao.
local lfsApi = nil

local function getLfsApi()
    if lfsApi then return lfsApi end
    local ok, api = pcall(require, "LFS_API")
    if ok and api then
        lfsApi = api
        print("[HWNetBridge] LFS_API detectada e carregada.")
    end
    return lfsApi
end

local function compactFactionMembers(faccao)
    local members = {}
    if type(faccao.members) ~= "table" then return members end

    for _, member in ipairs(faccao.members) do
        members[#members + 1] = {
            username = member.username and tostring(member.username) or nil,
            displayName = member.displayName and tostring(member.displayName) or nil,
            steamId = member.steamId and tostring(member.steamId) or nil,
            accountId = member.accountId and tostring(member.accountId) or nil,
            role = member.role and tostring(member.role) or nil,
            owner = member.owner == true or member.isOwner == true,
            online = member.online == true
        }
    end

    return members
end

local function writeFactions()
    local api = getLfsApi()
    if not api then
        writeFile("hwbridge_factions.json", '{"available":false,"factions":[]}')
        return
    end

    local ok, factions = pcall(api.getFactions)
    if not ok or type(factions) ~= "table" then
        writeFile("hwbridge_factions.json", '{"available":false,"factions":[]}')
        return
    end

    local payload = { available = true, factions = {} }
    for _, faccao in ipairs(factions) do
        payload.factions[#payload.factions + 1] = {
            id = faccao.id,
            name = faccao.name,
            tag = faccao.tag,
            owner = faccao.owner,
            members = compactFactionMembers(faccao),
            memberCount = faccao.memberCount,
            score = (faccao.score and faccao.score.current) or 0,
            colorHex = faccao.color and faccao.color.hex or nil,
            claimedTiles = (faccao.territory and faccao.territory.claimedTiles) or 0
        }
    end

    if #payload.factions == 0 then
        writeFile("hwbridge_factions.json", '{"available":true,"factions":[]}')
        return
    end

    local ok2, json = pcall(function() return api.toJSON(payload, false) end)
    if ok2 and json then
        writeFile("hwbridge_factions.json", json)
    end
end

local function bridgeTick()
    local ok, err = pcall(function()
        writeHeartbeat()
        processInbox()
        collectPlayersAndDetectDeaths()
        writeEvents()
        writeFactions()
    end)

    if not ok then
        print("[HWNetBridge] ERRO no tick: " .. tostring(err))
    end
end

Events.OnServerStarted.Add(bridgeTick)
Events.EveryOneMinute.Add(bridgeTick)
print("[HWNetBridge] Bridge inicializada (tick a cada 1 minuto de jogo).")
