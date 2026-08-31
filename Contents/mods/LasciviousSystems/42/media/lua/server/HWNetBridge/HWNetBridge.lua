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
-- Comandos aceitos no inbox (campo "type"): "ping" e "grant_discord_reward" (credita
-- bonus de verificacao Discord na Lascivious Shop via LasciviousShop.queueCredits,
-- ver CLAUDE_DISCORD_VERIFICATION_SHOP_REWARD.md). So um comando em voo por vez -- o
-- lado Node so pode escrever um novo comando depois de ler o resultado do anterior.

local okSteamIdModule, SteamIdModule = pcall(require, "LasciviousSystems_SteamId")
local SteamId = okSteamIdModule and SteamIdModule or LasciviousSystemsSteamId

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
    if value == nil then return nil end
    local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
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

local DISCORD_VERIFICATION_REWARD = 300

-- Credita o bonus de verificacao Discord na Lascivious Shop. SteamID e a identidade
-- canonica (funciona mesmo offline/sem conta ainda, ver LasciviousShop.queueCredits);
-- username e so um extra pra loja tentar atualizar a UI na hora se o jogador estiver
-- online. Idempotencia ("ja recebeu?") NAO e responsabilidade daqui -- isso e controlado
-- do lado Node (steamverify/lib/rewardStore.js), que so manda esse comando uma vez por
-- SteamID depois de confirmar sucesso.
local function grantDiscordVerificationReward(steamId, username, commandId)
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
    if type(username) == "string" and username ~= "" then
        identity.username = username
    end

    if type(LasciviousShop.grantExternalRewardOnce) == "function" then
        return LasciviousShop.grantExternalRewardOnce(identity, "discord_verification", DISCORD_VERIFICATION_REWARD, commandId)
    end
    if type(LasciviousShop.queueCredits) == "function" then
        return LasciviousShop.queueCredits(identity, DISCORD_VERIFICATION_REWARD, "discord_verification")
    end
    return false, "shop_api_unavailable"
end

local function processInbox()
    local content = readFile("hwbridge_inbox.json")
    if content == "" then return end

    local id = content:match('"id"%s*:%s*"([^"]+)"')
    local ctype = content:match('"type"%s*:%s*"([^"]+)"')

    if not id or id == lastProcessedId then return end
    lastProcessedId = id

    print("[HWNetBridge] Comando recebido: id=" .. tostring(id) .. " type=" .. tostring(ctype))

    local success = "false"
    local message = "tipo de comando desconhecido: " .. tostring(ctype)
    local queued = "false"
    local accountKey = ""
    local rewardUsername = ""

    if ctype == "ping" then
        success = "true"
        message = "pong"
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

        local ok, err, info
        if not steamId and hasNumericSteamId(content) then
            ok, err = false, "invalid_steam_id_type"
        else
            ok, err, info = grantDiscordVerificationReward(steamId, username, id)
        end
        if ok then
            success = "true"
            queued = (info and info.queued) and "true" or "false"
            if queued == "true" and steamId then
                success = "false"
                message = "unexpected_queued_steam_identity"
            elseif info and info.alreadyApplied then
                message = "already_applied"
            else
                message = queued == "true" and "queued" or "applied"
            end
            accountKey = info and info.accountKey or ""
            rewardUsername = info and info.username or username or ""
        else
            success = "false"
            message = tostring(err)
        end
    end

    local resultJson = string.format(
        '{"type":"command_result","id":"%s","success":%s,"message":"%s","queued":%s,"accountKey":"%s","username":"%s"}',
        id, success, jsonEscape(message), queued, jsonEscape(accountKey), jsonEscape(rewardUsername)
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
