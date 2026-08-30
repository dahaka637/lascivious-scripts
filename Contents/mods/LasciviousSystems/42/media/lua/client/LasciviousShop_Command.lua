if isServer() then return end

require "Chat/ISChat"
require "LasciviousShop_Window"
local ChatRouter = require "LasciviousSystems_ChatRouter"

-- Build 42 sends unknown slash commands to the engine's closed command list.
-- Intercept /shop before that fallback while chaining any hook installed by
-- another mod. Exact matching avoids swallowing commands with similar prefixes.
ChatRouter.register("shop", function(chat, value)
    if type(value) == "string" and string.lower(value):match("^%s*/shop%s*$") then
        chat.textEntry:setText("")
        chat:unfocus()
        LasciviousShopWindow.toggle()
        return true
    end
    return false
end)
