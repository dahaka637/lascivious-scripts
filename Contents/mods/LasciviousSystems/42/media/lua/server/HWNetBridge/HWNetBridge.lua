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
-- "bind_pz_identity" (so registra o vinculo verificado username<->steam:<id> na Identity V2
-- -- NAO credita nada; existe porque getSteamIDFromUsername() exige GameClient.client==true
-- (confirmado via javap em LuaManager$GlobalObject) e por isso NUNCA funciona a partir de
-- Lua server-side num dedicated de verdade -- o bot e a unica fonte de SteamID exato pra
-- esses jogadores), e "discord_reward_admin" (inspecionar/limpar/listar receipts de
-- discord_verification -- ver LasciviousShop.adminDiscordReward e
-- HWNetBridge_Discord_Reward_Admin.md; NUNCA mexe no ledger financeiro, so no receipt
-- administrativo). So um comando em voo por vez -- o lado Node so pode escrever um novo
-- comando depois de ler o resultado do anterior.

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

-- ============================================================================
-- AVISO PERMANENTE DO DONO DO PROJETO (2026-09-01) -- NAO REMOVER ESTE BLOCO
-- ============================================================================
-- Depois de uma saga longa e desgastante em cima da recompensa de verificacao
-- do Discord -- split-brain de identidade SteamID, depois um bug de credito
-- duplicado a cada restart do servidor (ver commit ef3c0aa e o mesmo aviso em
-- LasciviousShop_Server.lua, acima de EXTERNAL_REWARDS) -- o dono do projeto
-- foi explicito: ele NUNCA MAIS, EM HIPOTESE ALGUMA, vai mexer de novo nisso,
-- e QUALQUER sessao futura (Claude, Codex, ou qualquer outra ferramenta) esta
-- PROIBIDA de tocar em grantDiscordVerificationReward, bindPzIdentity, ou nos
-- comandos grant_discord_reward/bind_pz_identity/discord_reward_admin --
-- EXCETO se o pedido explicito dele for apagar tudo isso por completo e de
-- vez. Nao "corrigir mais um detalhezinho". Nao "melhorar". Nada. Se algo
-- aqui parecer quebrado, pergunte se ele quer isso REMOVIDO POR COMPLETO --
-- nunca ofereça consertar de novo.
-- ============================================================================

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

-- Known, bounded shape from LasciviousShop.adminDiscordReward's "list" entries
-- -- not a general serializer, just this one small flat record.
local function jsonReceiptEntry(e)
    return string.format(
        '{"transactionKey":"%s","accountKey":"%s","steamId":"%s","status":"%s","amount":%s,"rewardType":"%s","externalId":"%s"}',
        jsonEscape(e.transactionKey), jsonEscape(e.accountKey), jsonEscape(e.steamId or ""),
        jsonEscape(e.status), jsonNumber(e.amount), jsonEscape(e.rewardType), jsonEscape(e.externalId or "")
    )
end

local function processInbox()
    local content = readFile("hwbridge_inbox.json")
    if content == "" then return end

    local id = content:match('"id"%s*:%s*"([^"]+)"')
    local ctype = content:match('"type"%s*:%s*"([^"]+)"')

    if not id or id == lastProcessedId then return end
    lastProcessedId = id

    print("[HWNetBridge] Comando recebido: id=" .. tostring(id) .. " type=" .. tostring(ctype))

    -- Covered by the DO NOT TOUCH warning above grantDiscordVerificationReward
    -- further up this file -- read that before changing anything below.
    --
    -- discord_reward_admin's response shape (a flat record for inspect/clear/
    -- clear_all, an array of flat records for list) doesn't fit the shared
    -- reward/bind template below, so it builds and writes its own response
    -- and returns here instead of falling through. Read-only for inspect/
    -- list; clear/clear_all only ever delete data.externalRewards[...]
    -- receipt entries via LasciviousShop.adminDiscordReward -- see that
    -- function's own comment for why that is always safe (never touches the
    -- account's own transaction ledger/balance).
    if ctype == "discord_reward_admin" then
        local action = jsonQuotedString(content, "action") or ""
        local steamId = jsonQuotedString(content, "steamId")
            or jsonQuotedString(content, "steamID64")
            or jsonQuotedString(content, "steamID")
            or jsonQuotedString(content, "steam_id_64")
            or jsonQuotedString(content, "steam_id")
            or jsonQuotedString(content, "steam64")
            or jsonQuotedString(content, "steam")
            or jsonQuotedString(content, "steamid")

        local resultJson
        if not (LasciviousShop and type(LasciviousShop.adminDiscordReward) == "function") then
            resultJson = string.format('{"type":"command_result","id":"%s","success":false,"message":"shop_unavailable"}', id)
        elseif action ~= "inspect" and action ~= "clear" and action ~= "list" and action ~= "clear_all" then
            resultJson = string.format('{"type":"command_result","id":"%s","success":false,"message":"invalid_action"}', id)
        elseif (action == "inspect" or action == "clear") and not steamId and hasNumericSteamId(content) then
            resultJson = string.format('{"type":"command_result","id":"%s","success":false,"message":"invalid_steam_id_type"}', id)
        else
            local okCall, r = pcall(LasciviousShop.adminDiscordReward, action, steamId)
            if not okCall or type(r) ~= "table" then
                print("[HWNetBridge] discord_reward_admin erro interno: " .. tostring(r))
                resultJson = string.format('{"type":"command_result","id":"%s","success":false,"message":"internal_error"}', id)
            elseif r.success ~= true then
                resultJson = string.format('{"type":"command_result","id":"%s","success":false,"action":"%s","message":"%s"}',
                    id, jsonEscape(action), jsonEscape(r.message or "invalid_action"))
            elseif action == "inspect" and r.exists then
                resultJson = string.format(
                    '{"type":"command_result","id":"%s","success":true,"action":"inspect","steamId":"%s",' ..
                    '"accountKey":"%s","transactionKey":"%s","exists":true,"status":"%s","amount":%s,' ..
                    '"rewardType":"%s","externalId":"%s"}',
                    id, jsonEscape(r.steamId), jsonEscape(r.accountKey), jsonEscape(r.transactionKey),
                    jsonEscape(r.status), jsonNumber(r.amount), jsonEscape(r.rewardType), jsonEscape(r.externalId or ""))
            elseif action == "inspect" then
                resultJson = string.format(
                    '{"type":"command_result","id":"%s","success":true,"action":"inspect","steamId":"%s",' ..
                    '"accountKey":"%s","transactionKey":"%s","exists":false}',
                    id, jsonEscape(r.steamId), jsonEscape(r.accountKey), jsonEscape(r.transactionKey))
            elseif action == "clear" and r.removed == 1 then
                resultJson = string.format(
                    '{"type":"command_result","id":"%s","success":true,"action":"clear","steamId":"%s",' ..
                    '"removed":1,"transactionKey":"%s"}',
                    id, jsonEscape(r.steamId), jsonEscape(r.transactionKey))
            elseif action == "clear" then
                resultJson = string.format(
                    '{"type":"command_result","id":"%s","success":true,"action":"clear","steamId":"%s",' ..
                    '"removed":0,"message":"not_found"}',
                    id, jsonEscape(r.steamId))
            elseif action == "list" then
                local parts = {}
                for _, e in ipairs(r.entries or {}) do parts[#parts + 1] = jsonReceiptEntry(e) end
                resultJson = string.format(
                    '{"type":"command_result","id":"%s","success":true,"action":"list","count":%d,"entries":[%s]}',
                    id, r.count or 0, table.concat(parts, ","))
            else -- clear_all
                resultJson = string.format(
                    '{"type":"command_result","id":"%s","success":true,"action":"clear_all","removed":%d}',
                    id, r.removed or 0)
            end
        end

        writeFile("hwbridge_outbox_result.json", resultJson)
        print("[HWNetBridge] Respondido (discord_reward_admin): id=" .. tostring(id) .. " action=" .. tostring(action))
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
