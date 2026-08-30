-- Abre o painel do /kit sozinho pouco depois do personagem nascer, pra quem
-- nao le o chat ou nao sabe do comando. HardcoreKitsConfig.AutoOpenOnSpawnEnabled
-- (sandbox, default true).
--
-- Checagem antes de abrir: pede o state ao servidor (mesmo
-- HardcoreKitsClient.requestState que o resto do painel usa) e só abre se
-- initialKitClaimedByCharacter e initialKitClaimedByAccount vierem false -- a
-- mesma checagem que o servidor usa pra decidir se o Kit Inicial ainda pode ser
-- resgatado. Personagem/conta que ja pegou o kit nunca reabre sozinho, não
-- importa quantas vezes o gatilho disparar.
--
-- Atraso em TEMPO REAL (getTimestampMs()), nao contagem de ticks -- um
-- delay fixo de ticks pode variar de duracao real dependendo do framerate
-- no momento (ex: logo apos o spawn, com o mundo ainda carregando ao redor).
--
-- DUAS fases, nao uma: primeiro ESPERA o personagem estar de fato carregado
-- no mundo (getPlayer() valido + getCurrentSquare() valido -- mesmo par de
-- checagem usado pelo proprio jogo em ISWorldObjectContextMenu.lua pra
-- confirmar que um IsoPlayer ja tem posicao real, nao um objeto ainda em
-- construcao), e SO DEPOIS disso comeca a contar os 2 segundos. Bug
-- corrigido: a versao anterior comecava a contar os 2s no instante em que
-- OnCreatePlayer/OnGameStart disparava, nao em quando o personagem realmente
-- estava pronto -- funcionava bem num personagem novo apos morte (o mundo ja
-- estava carregado havia tempo), mas no PRIMEIRO personagem da sessao, o
-- evento pode disparar bem antes do personagem estar de fato carregado no
-- mundo, fazendo os 2s se esgotarem cedo demais/na hora errada.
--
-- DOIS gatilhos, de proposito, ambos chamando a MESMA scheduleAutoOpen():
--   1) Events.OnCreatePlayer -- o caso normal (personagem morre, cria outro
--      na mesma sessao). Documentado como podendo disparar mais de uma vez
--      pro mesmo spawn (ex: reconexao de personagem ja existente).
--   2) Events.OnGameStart -- REFORCO especifico pro bug "auto-open nao
--      funciona no PRIMEIRO personagem da sessao, so a partir do segundo"
--      (reportado pelo usuario). Teoria: os arquivos Lua do mod, incluindo
--      este, so terminam de registrar seus listeners durante a
--      inicializacao do jogo -- e ha indicio de que a criacao do PRIMEIRO
--      personagem de uma sessao nova acontece cedo o bastante nesse
--      processo pra, as vezes, disparar OnCreatePlayer ANTES desse registro
--      terminar, perdendo o evento pra sempre pra aquele spawn especifico.
--      OnGameStart e o mesmo evento que HardcoreKits_SandboxBridge/
--      Validation ja usam com sucesso (inclusive em singleplayer -- vanilla
--      ISChat.lua tambem usa, confirmando que dispara nos dois modos,
--      SP e MP), e dispara DEPOIS de todo o carregamento estar completo.
-- Chamar os dois nunca duplica o efeito visivel: HardcoreKitsWindow.open()
-- e idempotente (ver HardcoreKits_Window.lua) -- se o OnCreatePlayer ja
-- tiver aberto certo, o OnGameStart rodar depois (ou vice-versa) nao fecha
-- nem reabre nada.
require "HardcoreKits_Config"
require "HardcoreKits_Client"
require "HardcoreKits_Window"
require "HardcoreKits_Danger"

HardcoreKitsAutoOpen = HardcoreKitsAutoOpen or {}
if HardcoreKitsAutoOpen.activeLoadWait and Events.OnTick.Remove then
    Events.OnTick.Remove(HardcoreKitsAutoOpen.activeLoadWait)
end
if HardcoreKitsAutoOpen.activeOpenCheck and Events.OnTick.Remove then
    Events.OnTick.Remove(HardcoreKitsAutoOpen.activeOpenCheck)
end
if HardcoreKitsAutoOpen.createPlayerHandler and Events.OnCreatePlayer.Remove then
    Events.OnCreatePlayer.Remove(HardcoreKitsAutoOpen.createPlayerHandler)
end
if HardcoreKitsAutoOpen.gameStartHandler and Events.OnGameStart.Remove then
    Events.OnGameStart.Remove(HardcoreKitsAutoOpen.gameStartHandler)
end
HardcoreKitsAutoOpen.activeLoadWait = nil
HardcoreKitsAutoOpen.activeOpenCheck = nil

local LOAD_WAIT_GIVE_UP_MS = 20000 -- desiste de esperar o personagem carregar (algo esta muito errado)
local DELAY_MS = 2000
local GIVE_UP_MS = 10000 -- se o servidor nunca responder, desiste em silencio
local activeLoadWait = nil
local activeOpenCheck = nil

local function removeTick(callback)
    if callback then Events.OnTick.Remove(callback) end
end

-- fase 2: personagem confirmado carregado -- SO AGORA comeca a contar os 2s
-- (mesma logica de antes, so que o "agora" de referencia mudou de "quando o
-- evento disparou" pra "quando o personagem realmente ficou pronto")
local function beginPostLoadCountdown()
    removeTick(activeOpenCheck)
    activeOpenCheck = nil
    HardcoreKitsAutoOpen.activeOpenCheck = nil
    local requestedAtMs = getTimestampMs()
    local targetMs = requestedAtMs + DELAY_MS
    local giveUpMs = requestedAtMs + GIVE_UP_MS
    HardcoreKitsClient.requestState()

    local function checkOpen()
        local now = getTimestampMs()
        if now < targetMs then return end
        if now > giveUpMs then
            Events.OnTick.Remove(checkOpen)
            if activeOpenCheck == checkOpen then
                activeOpenCheck = nil
                HardcoreKitsAutoOpen.activeOpenCheck = nil
            end
            return
        end
        -- espera a resposta do servidor chegar (deve ser quase instantanea) --
        -- so aceita um state que chegou DEPOIS do request feito aqui em cima,
        -- pra nunca usar um valor antigo por coincidencia
        local state = HardcoreKitsClient.state
        if not state or HardcoreKitsClient.stateReceivedAtMs < requestedAtMs then return end

        Events.OnTick.Remove(checkOpen)
        if activeOpenCheck == checkOpen then
            activeOpenCheck = nil
            HardcoreKitsAutoOpen.activeOpenCheck = nil
        end
        if state.initialKitClaimedByCharacter ~= true and state.initialKitClaimedByAccount ~= true then
            -- Checagem UNICA, pedida explicitamente pelo usuario -- sem retry
            -- nem espera por "ficar seguro": se tem zumbi por perto bem neste
            -- instante, so nao abre sozinho desta vez, e fica por conta do
            -- jogador abrir manualmente (/kit ou o botao da barra lateral)
            -- quando quiser. Evita popar a interface na cara de quem esta
            -- sendo perseguido justamente ao spawnar.
            local ok, player = pcall(getPlayer)
            local danger = ok and player and HardcoreKitsConfig.AutoOpenZombieCheckEnabled == true
                and HardcoreKitsDanger.zombiesNear(player, HardcoreKitsConfig.AutoOpenZombieCheckRadius)
            if not danger then
                HardcoreKitsWindow.open()
            end
        end
    end
    activeOpenCheck = checkOpen
    HardcoreKitsAutoOpen.activeOpenCheck = checkOpen
    Events.OnTick.Add(checkOpen)
end

-- fase 1: espera o personagem estar de fato carregado no mundo (posicao
-- valida), antes de comecar a contar qualquer coisa
local function scheduleAutoOpen()
    if HardcoreKitsConfig.AutoOpenOnSpawnEnabled ~= true then return end

    -- OnCreatePlayer e OnGameStart podem apontar para o mesmo spawn. Mantem
    -- uma unica espera/checagem viva, evitando requests e closures duplicadas.
    removeTick(activeLoadWait)
    removeTick(activeOpenCheck)
    activeLoadWait = nil
    activeOpenCheck = nil
    HardcoreKitsAutoOpen.activeLoadWait = nil
    HardcoreKitsAutoOpen.activeOpenCheck = nil

    local loadGiveUpAtMs = getTimestampMs() + LOAD_WAIT_GIVE_UP_MS

    local function waitForCharacterLoaded()
        local now = getTimestampMs()
        if now > loadGiveUpAtMs then
            Events.OnTick.Remove(waitForCharacterLoaded)
            if activeLoadWait == waitForCharacterLoaded then
                activeLoadWait = nil
                HardcoreKitsAutoOpen.activeLoadWait = nil
            end
            return
        end
        local ok, player = pcall(getPlayer)
        if not ok or not player then return end
        local ok2, square = pcall(function() return player:getCurrentSquare() end)
        if not ok2 or not square then return end -- ainda carregando

        Events.OnTick.Remove(waitForCharacterLoaded)
        if activeLoadWait == waitForCharacterLoaded then
            activeLoadWait = nil
            HardcoreKitsAutoOpen.activeLoadWait = nil
        end
        beginPostLoadCountdown()
    end
    activeLoadWait = waitForCharacterLoaded
    HardcoreKitsAutoOpen.activeLoadWait = waitForCharacterLoaded
    Events.OnTick.Add(waitForCharacterLoaded)
end

local function onCreatePlayer(playerIndex, player)
    scheduleAutoOpen()
end

HardcoreKitsAutoOpen.createPlayerHandler = onCreatePlayer
HardcoreKitsAutoOpen.gameStartHandler = scheduleAutoOpen
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnGameStart.Add(scheduleAutoOpen)
