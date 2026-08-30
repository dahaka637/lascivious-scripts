-- One reload-safe owner for the all-in-one mod's slash commands.
--
-- Three independent wrappers around ISChat.onCommandEntered worked on the
-- initial alphabetical load, but a Lua reload rebuilt/lost parts of that chain:
-- /shop could disappear and /kit accumulated another wrapper each time.  Keep
-- one stable wrapper and let each subsystem replace only its named handler.
if isServer() then return {} end

require "Chat/ISChat"

LasciviousSystemsChatRouter = LasciviousSystemsChatRouter or {
    handlers = {},
    order = {},
}
local Router = LasciviousSystemsChatRouter

function Router.register(id, handler)
    if type(id) ~= "string" or id == "" or type(handler) ~= "function" then return false end
    if Router.handlers[id] == nil then Router.order[#Router.order + 1] = id end
    Router.handlers[id] = handler
    return true
end

if not Router.wrapper then
    -- Preserve whatever vanilla/third-party hook was already installed before
    -- this all-in-one router. It remains the fallback for every unhandled line.
    Router.base = ISChat.onCommandEntered
    Router.wrapper = function(self)
        local instance = ISChat.instance
        local text = instance and instance.textEntry and instance.textEntry:getText()
        if type(text) == "string" then
            for _, id in ipairs(Router.order) do
                local handler = Router.handlers[id]
                if handler then
                    local ok, handled = pcall(handler, instance, text, self)
                    if not ok then
                        print("[LasciviousSystems] chat command handler '" .. tostring(id)
                            .. "' failed: " .. tostring(handled))
                    elseif handled == true then
                        return
                    end
                end
            end
        end
        if Router.base then return Router.base(self) end
    end
end

-- Install only when our own wrapper still owns the table slot or on its first
-- load. If another mod deliberately wrapped us afterwards, leave that outer
-- wrapper intact; it will still delegate into this stable function.
if ISChat.onCommandEntered == Router.base or ISChat.onCommandEntered == Router.wrapper then
    ISChat.onCommandEntered = Router.wrapper
end

local function attachLiveEntry()
    local instance = ISChat.instance
    if instance and instance.textEntry then
        -- Use the current outermost table hook so third-party wrappers installed
        -- after ours are not bypassed on an already-created chat widget.
        instance.textEntry.onCommandEntered = ISChat.onCommandEntered
    end
end

if Router.gameStartHook and Events.OnGameStart.Remove then
    Events.OnGameStart.Remove(Router.gameStartHook)
end
Router.gameStartHook = attachLiveEntry
Events.OnGameStart.Add(attachLiveEntry)
attachLiveEntry()

return Router
