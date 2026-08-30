-- Aviso no chat quando um personagem novo nasce, lembrando de digitar /kit.
-- E so um lembrete cosmetico -- qualquer falha aqui deve ficar em silencio e
-- nunca atrapalhar a criacao do personagem.
--
-- Tecnica: escreve direto em ISChat.instance.chatText (a aba JA ativa, sem
-- precisar procurar por tabID -- a v1 usava ISChat.addLineInChat(msg, tabID),
-- que buscava uma aba por tabID e nunca encontrava nada em teste real,
-- gerando erro Lua a cada tentativa -- ver ISChat.lua:724), replicando so a
-- parte segura do que ISChat.addLineInChat faz internamente
-- (media/lua/client/Chat/ISChat.lua, ~linhas 736-758): empilha a linha em
-- chatTextLines, remonta chatText.text e chama chatText:paginate().
--
-- v6: depois de 5 tentativas com texto colorido (tag <RGB:r,g,b>) todas
-- falharem em campo por um bug de espacamento/truncamento nunca
-- definitivamente identificado (espaco simples, espaco duplo, e ate trocar
-- espaco por traco como separador -- nenhum resolveu, o ultimo ate piorou,
-- cortando pedaco da mensagem), a decisao foi abandonar cor e tag por
-- completo: texto simples, sem NENHUMA tag <RGB:...>, so getText() com
-- espaco literal normal entre as palavras -- o caminho mais basico e
-- testado (e' exatamente o que centenas de outras linhas de chat vanilla
-- fazem sem tag nenhuma), eliminando de vez qualquer interacao com o
-- mecanismo de tag que causava o problema.
require "HardcoreKits_Config"

HardcoreKitsWelcome = HardcoreKitsWelcome or {}
if HardcoreKitsWelcome.retryHandler and Events.OnTick.Remove then
    Events.OnTick.Remove(HardcoreKitsWelcome.retryHandler)
end
if HardcoreKitsWelcome.createPlayerHandler and Events.OnCreatePlayer.Remove then
    Events.OnCreatePlayer.Remove(HardcoreKitsWelcome.createPlayerHandler)
end

-- mensagem padrao, montada na hora (nunca em cache) via getText() -- assim
-- ela sai no idioma que o jogador tem configurado agora no jogo (EN/PTBR,
-- ver shared/Translate/*/UI.json), mesmo que ele tenha trocado o idioma
-- depois do ultimo boot. So e chamada quando o dono do servidor NAO
-- sobrescreveu HardcoreKitsConfig.WelcomeMessageText com um texto fixo.
local function buildDefaultWelcomeMessage()
    return "[" .. getText("UI_HardcoreKits_ChatTag") .. "] "
        .. getText("UI_HardcoreKits_WelcomeMessagePrefix") .. " /kit "
        .. getText("UI_HardcoreKits_WelcomeMessageSuffix")
end

local function postToChat()
    local ok = pcall(function()
        local chat = ISChat.instance
        if not chat then error("sem ISChat.instance ainda") end

        if not chat.chatText then
            if not chat.defaultTab then error("sem defaultTab ainda") end
            chat.chatText = chat.defaultTab
            chat:onActivateView()
        end
        local chatText = chat.chatText
        if not chatText or not chatText.chatTextLines then error("chatText incompleto ainda") end

        local vscroll = chatText.vscroll
        local scrolledToBottom = (chatText:getScrollHeight() <= chatText:getHeight()) or (vscroll and vscroll.pos == 1)

        local message = HardcoreKitsConfig.WelcomeMessageText or buildDefaultWelcomeMessage()
        table.insert(chatText.chatTextLines, message .. " <LINE> ")
        if ISChat.maxLine and #chatText.chatTextLines > ISChat.maxLine then
            table.remove(chatText.chatTextLines, 1)
        end

        local newText = ""
        for i, v in ipairs(chatText.chatTextLines) do
            if i == #chatText.chatTextLines then
                v = string.gsub(v, " <LINE> $", "")
            end
            newText = newText .. v
        end
        chatText.text = newText
        chatText:paginate()
        if scrolledToBottom then
            chatText:setYScroll(-10000)
        end
    end)
    return ok
end

-- a UI de chat pode ainda nao existir no exato instante em que o personagem
-- e criado (transicao de tela); tenta por alguns segundos e desiste
-- silenciosamente se nunca aparecer
local pendingTicks = 0
local MAX_TICKS = 180 -- ~3s a 60fps

local function onTickRetry()
    pendingTicks = pendingTicks + 1
    local ok, done = pcall(postToChat)
    if (ok and done) or pendingTicks > MAX_TICKS then
        Events.OnTick.Remove(onTickRetry)
        if HardcoreKitsWelcome.retryHandler == onTickRetry then
            HardcoreKitsWelcome.retryHandler = nil
        end
    end
end

local function onCreatePlayer(playerIndex, player)
    if HardcoreKitsConfig.WelcomeMessageEnabled ~= true then return end
    -- em singleplayer nao existe "chat" de verdade entre jogadores -- o
    -- lembrete de /kit nao faz sentido nesse contexto, entao nem tenta
    if not isMultiplayer() then return end
    pendingTicks = 0
    Events.OnTick.Remove(onTickRetry) -- evita empilhar retries em spawns rapidos (ex: multiplos personagens)
    HardcoreKitsWelcome.retryHandler = onTickRetry
    Events.OnTick.Add(onTickRetry)
end

HardcoreKitsWelcome.createPlayerHandler = onCreatePlayer
Events.OnCreatePlayer.Add(onCreatePlayer)
