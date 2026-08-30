-- Client side of moderation: carries out what the server can only order
-- (vanilla ban/kick, evidence screenshot, self disconnect),
-- shows warnings and enforces the chat mute.
require "Aegis/AegisTheme"

AegisModClient = AegisModClient or {}

-- active mutes synced from the server: username -> expiry in client millis
local muteUntil = {}

-- ---------- chat mute ----------
-- Incoming uses vanilla's own suppression (ISChat.mutedUsers),
-- outgoing wraps onCommandEntered. Both only after OnGameStart,
-- before that ISChat.instance does not exist.
local function isMuted(name)
    local expiry = muteUntil[name]
    return expiry ~= nil and (expiry == 0 or expiry > getTimestampMs())
end

local function syncVanillaMutes()
    if not ISChat or not ISChat.instance then return end
    ISChat.instance.mutedUsers = ISChat.instance.mutedUsers or {}
    for name in pairs(ISChat.instance.mutedUsers) do
        -- only clear the ones set by Aegis, leave foreign entries alone
        if ISChat.instance.aegisMuted and ISChat.instance.aegisMuted[name] then
            ISChat.instance.mutedUsers[name] = nil
        end
    end
    ISChat.instance.aegisMuted = {}
    for name in pairs(muteUntil) do
        if isMuted(name) then
            ISChat.instance.mutedUsers[name] = true
            ISChat.instance.aegisMuted[name] = true
        end
    end
end

local function patchOutgoing()
    if not ISChat or ISChat.aegisWrapped then return end
    ISChat.aegisWrapped = true
    local original = ISChat.onCommandEntered
    ISChat.onCommandEntered = function(self)
        local me = getPlayer() and getPlayer():getUsername()
        if me and isMuted(me) then
            local text = self and self.getInternalText and self:getInternalText() or ""
            -- still allow slash commands, only block actual talking
            if text ~= "" and text:sub(1, 1) ~= "/" then
                if self and self.clear then self:clear() end
                if ChatManager then
                    pcall(function()
                        ChatManager.getInstance():showInfoMessage(getText("UI_Aegis_YouAreMuted"))
                    end)
                end
                return
            end
        end
        return original(self)
    end
    -- the chat instance keeps a copy of the function as a field
    if ISChat.instance and ISChat.instance.textEntry then
        ISChat.instance.textEntry.onCommandEntered = ISChat.onCommandEntered
    end
end

-- ---------- warning overlay ----------
AegisWarning = ISPanel:derive("AegisWarning")

function AegisWarning.show(reason, count)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local w, h = 520, 150
    local o = ISPanel:new(math.floor((sw - w) / 2), math.floor(sh * 0.28), w, h)
    setmetatable(o, AegisWarning)
    AegisWarning.__index = AegisWarning
    o.background = false
    o.reason = reason or ""
    o.count = count or 1
    o.untilMs = getTimestampMs() + 9000
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    o.okBtn = AegisButton:new(math.floor((w - 140) / 2), h - 44, 140, 32, getText("UI_Aegis_Understood"), nil, o, function(p) p:removeFromUIManager() end)
    o.okBtn.style = "gold"
    o:addChild(o.okBtn)
    return o
end

function AegisWarning:prerender()
    local c = Aegis.col
    Aegis.shadow(self, 0, 0, self.width, self.height, 30, 0.7)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 12, 1, c.danger, c.bg)
    Aegis.icon(self, "kick", 20, 18, 22, 1, c.danger)
    Aegis.text(self, getText("UI_Aegis_WarningTitle"), 52, 20, UIFont.Large, c.text)
    Aegis.text(self, getText("UI_Aegis_WarningCount") .. " " .. tostring(self.count), self.width - 20 - Aegis.strW(UIFont.Small, getText("UI_Aegis_WarningCount") .. " " .. tostring(self.count)), 26, UIFont.Small, c.muted)
    local reason = Aegis.fitText(self.reason ~= "" and self.reason or getText("UI_Aegis_NoReason"), UIFont.Medium, self.width - 40)
    Aegis.text(self, reason, 20, 60, UIFont.Medium, c.goldHi)
end

function AegisWarning:update()
    if getTimestampMs() > self.untilMs then self:removeFromUIManager() end
end

-- ---------- receiving server orders ----------
function AegisModClient.receive(command, args)
    if command == "noteData" then
        if AegisPagePlayers and AegisPagePlayers.instance then
            AegisPagePlayers.instance:receiveNote(args)
        end
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    if command == "enforcement" then
        -- the server has secured evidence, the actual enforcement happens here
        if args.shot then
            pcall(function() takeScreenshot(args.shot) end)
        end
        if args.command then
            SendCommandToServer(args.command)
        end
        local kindText = getText("UI_Aegis_Done_" .. tostring(args.kind)) or ""
        Aegis.showToast(kindText .. ": " .. tostring(args.target))
    elseif command == "forceDisconnect" then
        -- target client disconnects itself (only kick path without vanilla rights)
        local reason = args and args.reason or ""
        if ChatManager then
            pcall(function()
                ChatManager.getInstance():showInfoMessage(getText("UI_Aegis_YouWereRemoved") .. " " .. reason)
            end)
        end
        pcall(function() disconnect() end)
    elseif command == "warning" then
        AegisWarning.show(args and args.reason, args and args.count)
    elseif command == "muteSync" then
        muteUntil = {}
        if args and type(args.list) == "table" then
            for _, e in pairs(args.list) do
                if type(e) == "table" and e.user then
                    muteUntil[e.user] = (e.remaining == 0) and 0 or (getTimestampMs() + (tonumber(e.remaining) or 0) * 1000)
                end
            end
        end
        syncVanillaMutes()
    elseif command == "noteData" then
        AegisModClient.receive("noteData", args)
    elseif command == "noteSaved" then
        if AegisPagePlayers and AegisPagePlayers.instance then
            AegisPagePlayers.instance:receiveNoteSaved(args)
        end
    elseif command == "noteConflict" then
        if AegisPagePlayers and AegisPagePlayers.instance then
            AegisPagePlayers.instance:receiveNoteConflict(args)
        end
    elseif command == "banStatus" then
        if AegisPagePlayers and AegisPagePlayers.instance then
            AegisPagePlayers.instance:receiveBanStatus(args)
        end
    elseif command == "giveItems" then
        if args and args.ok then
            Aegis.showToast(getText("UI_Aegis_ItemsGiven") .. ": " .. tostring(args.total))
        end
    end
end)

-- chat patch only works once the chat instance exists; muteReq also in
-- solo, otherwise persisted mutes are never resynced after a restart
Events.OnGameStart.Add(function()
    patchOutgoing()
    syncVanillaMutes()
    sendClientCommand(getPlayer(), "AegisAdmin", "muteReq", {})
end)

-- clear expired mutes locally until the next server sync arrives
Events.EveryOneMinute.Add(function()
    local changed = false
    for name, expiry in pairs(muteUntil) do
        if expiry ~= 0 and expiry <= getTimestampMs() then
            muteUntil[name] = nil
            changed = true
        end
    end
    if changed then syncVanillaMutes() end
end)
