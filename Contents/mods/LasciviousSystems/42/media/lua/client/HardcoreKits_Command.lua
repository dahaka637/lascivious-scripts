-- Intercepta "/kit" digitado no chat e abre o painel, sem deixar o texto
-- cair no SendCommandToServer nativo (que so reconhece a lista fechada de
-- comandos do engine e rejeitaria "/kit" silenciosamente).
--
-- Confirmado lendo media/lua/client/Chat/ISChat.lua da build 42 instalada:
-- ISChat:onCommandEntered() (linha ~465) le o texto de
-- ISChat.instance.textEntry, e SO cai no SendCommandToServer nativo (linha
-- ~514) quando o texto comeca com "/" e nao bate com nenhuma chat-stream
-- conhecida (/s, /w, /f, ...). Interceptando aqui, antes desse fallback,
-- HardcoreKits pode tratar "/kit" como um comando proprio.
require "Chat/ISChat"
require "HardcoreKits_Window"
local ChatRouter = require "LasciviousSystems_ChatRouter"

ChatRouter.register("hardcore_kits", function(chat, text)
    if type(text) == "string" then
        -- comando exato "/kit" ou "/kits" (espacos em volta tolerados) --
        -- nunca intercepta prefixos parciais como "/kitchen" digitados por engano
        if text:match("^%s*/kits?%s*$") then
            chat.textEntry:setText("")
            chat:unfocus()
            HardcoreKitsWindow.toggle()
            return true
        end
    end
    return false
end)
