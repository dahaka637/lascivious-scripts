-- Entry point: golden stone button in the sidebar plus hotkey, and the
-- blue player panel button right below it
require "ISUI/ISEquippedItem"
require "Aegis/AegisTheme"
require "Aegis/AegisPlayerCore"
require "Aegis/AegisWindow"
require "Aegis/AegisPageDashboard"
require "Aegis/AegisPagePowers"
require "Aegis/AegisPagePlayers"
require "Aegis/AegisPageItems"
require "Aegis/AegisPageVehicles"
require "Aegis/AegisVehicleDetail"
require "Aegis/AegisPageWorld"
require "Aegis/AegisPageZones"
require "Aegis/AegisPageHorde"
require "Aegis/AegisPageServer"
require "Aegis/AegisPageSandbox"
require "Aegis/AegisPageLogs"
require "Aegis/AegisPageRoles"
require "Aegis/AegisModerationClient"

AegisHud = AegisHud or {}

function AegisHud.onButtonClick(equipped, button)
    AegisWindow.toggle()
end

function AegisHud.onPlayerButtonClick(equipped, button)
    if AegisPlayerWindow then AegisPlayerWindow.toggle() end
end

-- golden fullscreen banner for server announcements (restart notices),
-- visible to EVERY player, independent of the Aegis window
AegisBanner = ISPanel:derive("AegisBanner")

function AegisBanner.show(text)
    if not text or text == "" then return end
    if AegisBanner.instance then
        AegisBanner.instance:removeFromUIManager()
        AegisBanner.instance = nil
    end
    local sw = getCore():getScreenWidth()
    local w = math.max(360, Aegis.strW(UIFont.Large, text) + 80)
    local o = ISPanel:new(math.floor((sw - w) / 2), 96, w, 64)
    setmetatable(o, AegisBanner)
    AegisBanner.__index = AegisBanner
    o.background = false
    o.text = text
    o.untilMs = getTimestampMs() + 8000
    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)
    o.javaObject:setConsumeMouseEvents(false)
    AegisBanner.instance = o
    -- also to chat, for anyone looking elsewhere right now; ChatManager
    -- itself can be unavailable for a moment on some clients, and
    -- indexing it then throws even inside pcall's protection:
    -- PZ still surfaces the caught trace as an error popup)
    if ChatManager then
        pcall(function() ChatManager.getInstance():showInfoMessage(text) end)
    end
    return o
end

function AegisBanner:prerender()
    local c = Aegis.col
    Aegis.shadow(self, 0, 0, self.width, self.height, 24, 0.6)
    Aegis.roundFrame(self, 0, 0, self.width, self.height, 12, 0.97, c.gold, c.dark)
    Aegis.icon(self, "clock", 20, 20, 22, 1, c.gold)
    Aegis.textCentre(self, self.text, math.floor(self.width / 2) + 10,
        math.floor((self.height - Aegis.fontH(UIFont.Large)) / 2), UIFont.Large, c.goldHi)
end

function AegisBanner:update()
    if getTimestampMs() > self.untilMs then
        self:removeFromUIManager()
        if AegisBanner.instance == self then AegisBanner.instance = nil end
    end
end

-- ==================================================================
-- AegisHudDock: the two panel buttons in a small free floating dock.
-- They used to live inside the vanilla equipped-item bar and yield below
-- its lowest icon. Measuring that bar is a losing game: every sidebar
-- mod rearranges it and vanilla itself hides buttons in place while
-- hovered, so any anchor flickers sooner or later. Hence an own dock,
-- by default a bit left of the screen centre, draggable by its grip,
-- the spot kept in the prefs file
-- ==================================================================

AegisHudDock = ISPanel:derive("AegisHudDock")
AegisHudDock.instance = nil

local DOCK_BTN = 48
local DOCK_PAD = 4
local DOCK_GRIP = 14
local DOCK_W = DOCK_BTN + DOCK_PAD * 2

local function dockDefault()
    return math.floor(getCore():getScreenWidth() / 2) - 200, 16
end

local function dockCreate()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = tonumber(Aegis.getPref("hudDockX"))
    local y = tonumber(Aegis.getPref("hudDockY"))
    -- a spot stored under another resolution may lie off screen. Clamp it
    -- back in instead of discarding it: the folded dock is only the grip
    -- strip tall and could legally sit lower than a fixed limit allows,
    -- which threw the remembered spot away on every start
    if not x or not y then
        x, y = dockDefault()
    else
        local folded = Aegis.getPref("hudDockFolded") == "1"
        local h = folded and DOCK_GRIP or (DOCK_GRIP + DOCK_BTN + DOCK_PAD)
        x = math.max(0, math.min(x, sw - DOCK_W))
        y = math.max(0, math.min(y, sh - h))
    end
    local o = ISPanel:new(x, y, DOCK_W, DOCK_GRIP + DOCK_BTN + DOCK_PAD)
    setmetatable(o, AegisHudDock)
    AegisHudDock.__index = AegisHudDock
    o.background = false
    o.collapsed = Aegis.getPref("hudDockFolded") == "1"
    o:initialise()
    o:addToUIManager()
    -- same as the banner and the mini bar: the dock is born early and would
    -- otherwise sit at the bottom of the UI stack, where any window opened
    -- later swallows its clicks on the overlapped area, the
    -- FactionsFramework factions window for example. Its own
    -- bringToTop cannot fix that, the click never reaches the dock
    o:setAlwaysOnTop(true)
    AegisHudDock.instance = o

    local btn = ISButton:new(DOCK_PAD, DOCK_GRIP, DOCK_BTN, DOCK_BTN, "", o, AegisHud.onButtonClick)
    btn:initialise()
    btn:instantiate()
    btn:setImage(Aegis.tex("hud"))
    btn:setDisplayBackground(false)
    btn:ignoreWidthChange()
    btn:ignoreHeightChange()
    btn:setVisible(false)
    o:addChild(btn)
    o.aegisBtn = btn

    local pbtn = ISButton:new(DOCK_PAD, DOCK_GRIP, DOCK_BTN, DOCK_BTN, "", o, AegisHud.onPlayerButtonClick)
    pbtn:initialise()
    pbtn:instantiate()
    pbtn:setImage(Aegis.tex("hud_player"))
    pbtn:setDisplayBackground(false)
    pbtn:ignoreWidthChange()
    pbtn:ignoreHeightChange()
    pbtn:setVisible(false)
    o:addChild(pbtn)
    o.aegisPlayerBtn = pbtn
    return o
end

function AegisHudDock:prerender()
    local c = Aegis.col
    -- grip strip: the only place to grab, the buttons swallow their own
    -- clicks. Three dots so it reads as a handle; brighter under the mouse
    Aegis.roundRect(self, 0, 0, self.width, DOCK_GRIP - 2, 6, self:isMouseOver() and 0.9 or 0.45, c.card)
    for i = -1, 1 do
        self:drawRect(math.floor(self.width / 2) + i * 6 - 1, 5, 2, 2, 1, c.goldDim.r, c.goldDim.g, c.goldDim.b)
    end
end

function AegisHudDock:onMouseDown(x, y)
    self:bringToTop()
    self.dragging = true
    -- a click folds the dock, a drag moves it. Same button, so count the
    -- travelled pixels and only treat it as a click below the threshold
    self.moved = 0
end

function AegisHudDock:onMouseMove(dx, dy)
    if self.dragging then
        self.moved = (self.moved or 0) + math.abs(dx) + math.abs(dy)
        self:setX(self.x + dx)
        self:setY(self.y + dy)
    end
end

function AegisHudDock:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

local DRAG_SLOP = 3

local function dockDrop(self)
    if not self.dragging then return end
    self.dragging = false
    if (self.moved or 0) <= DRAG_SLOP then
        self.collapsed = not self.collapsed
        Aegis.setPref("hudDockFolded", self.collapsed and "1" or "0")
    end
    -- clamp back on screen, then remember the spot for the next session
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    self:setX(math.max(0, math.min(self.x, sw - self.width)))
    self:setY(math.max(0, math.min(self.y, sh - self.height)))
    Aegis.setPref("hudDockX", math.floor(self.x))
    Aegis.setPref("hudDockY", math.floor(self.y))
end

function AegisHudDock:onMouseUp(x, y) dockDrop(self) end
function AegisHudDock:onMouseUpOutside(x, y) dockDrop(self) end

-- visibility, images and stacking, every tick. The rights gates are the
-- same pair the bar version used: allowed() is the cheap client guess,
-- hasAnyArea() the server's confirmed answer, and the dock is only born
-- once one of the two buttons may actually show (lazy, the engine knows
-- the admin state well after UI bootstrap)
Events.OnTick.Add(function()
    local p = getPlayer()
    if not p then return end
    local adminVisible = Aegis.allowed(p) and Aegis.hasAnyArea()
    local playerVisible = AegisPlayerClient ~= nil and AegisPlayerClient.enabled() or false
    local dock = AegisHudDock.instance
    if not dock then
        if not (adminVisible or playerVisible) then return end
        local ok, made = pcall(dockCreate)
        if not ok or not made then return end
        dock = made
    end
    -- an invisible dock neither draws nor takes the mouse. Step aside
    -- entirely while the world map or the pause screen covers the game,
    -- alwaysOnTop would float the buttons over both
    local covered = (ISWorldMap_instance ~= nil and ISWorldMap_instance:isVisible())
        or (MainScreen ~= nil and MainScreen.instance ~= nil and MainScreen.instance:isVisible())
    dock:setVisible((adminVisible or playerVisible) and not covered)
    if covered then return end
    local btn, pbtn = dock.aegisBtn, dock.aegisPlayerBtn
    local folded = dock.collapsed == true
    btn:setVisible(adminVisible and not folded)
    pbtn:setVisible(playerVisible and not folded)
    -- losing the rights closes an open panel, exactly as before
    if not adminVisible and AegisWindow.instance then AegisWindow.instance:close() end
    if adminVisible then
        btn:setImage(AegisWindow.instance and Aegis.tex("hud_on") or Aegis.tex("hud"))
    end
    if playerVisible then
        local open = AegisPlayerWindow and AegisPlayerWindow.instance
        pbtn:setImage(open and Aegis.tex("hud_player_on") or Aegis.tex("hud_player"))
        -- blue rides below gold, or takes the top slot alone
        pbtn:setY(adminVisible and (DOCK_GRIP + DOCK_BTN + 8) or DOCK_GRIP)
    end
    local slots = (adminVisible and 1 or 0) + (playerVisible and 1 or 0)
    local h = DOCK_GRIP
    if not folded then
        h = h + slots * DOCK_BTN + (slots > 1 and 8 or 0) + DOCK_PAD
    end
    if dock:getHeight() ~= h then dock:setHeight(h) end
end)

-- hotkeys via the B42 mod options: F7 opens the admin panel, F6 the
-- player area. F1 to F5, F10 and F11 are taken by vanilla
if PZAPI and PZAPI.ModOptions then
    local opts = PZAPI.ModOptions:create("AegisAdmin", "Aegis Admin Suite")
    AegisHud.keybind = opts:addKeyBind("openPanel", getText("UI_Aegis_Hotkey"), Keyboard.KEY_F7, "")
    AegisHud.playerKeybind = opts:addKeyBind("openPlayerPanel", getText("UI_Aegis_HotkeyPlayer"), Keyboard.KEY_F6, "")
end

-- the player area has no rights gate: whoever is on the server has it,
-- the toggle itself refuses while the server has not granted the panel
Events.OnKeyPressed.Add(function(key)
    if not AegisHud.playerKeybind or key == 0 then return end
    if key ~= AegisHud.playerKeybind:getValue() then return end
    if AegisPlayerWindow then AegisPlayerWindow.toggle() end
end)

Events.OnKeyPressed.Add(function(key)
    if not AegisHud.keybind then return end
    if key ~= AegisHud.keybind:getValue() or key == 0 then return end
    if not Aegis.allowed(getPlayer()) or not Aegis.hasAnyArea() then return end
    -- the same key first exits photo mode without also toggling the
    -- panel (which is only hidden then, not closed)
    if AegisPhotoMode and AegisPhotoMode.isOn() then
        AegisPhotoMode.setOn(false)
        return
    end
    AegisWindow.toggle()
end)

-- pinned carry weight: the engine recomputes maxWeight from traits on
-- several sync events, the gaps made the inventory claim "full" with a
-- heavy pack. Pinning every tick closes the gaps; the
-- toast only fires when the value actually changes
local carryPin = nil

Events.OnTick.Add(function()
    if not carryPin then return end
    pcall(function()
        local p = getPlayer()
        if p and p:getMaxWeight() ~= carryPin then
            p:setMaxWeightBase(carryPin)
            p:setMaxWeight(carryPin)
        end
    end)
end)

-- return path for server commands: apply healing locally, report spawn results,
-- adopt Aegis rights and surface denials
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    if command == "heal" then
        AegisShared.fullHeal(getPlayer())
    elseif command == "carryWeight" then
        local value = math.floor(tonumber(args and args.value) or 0)
        if value >= 5 and value <= 1000 then
            local changed = carryPin ~= value
            carryPin = (value > 8) and value or nil
            pcall(function()
                local p = getPlayer()
                p:setMaxWeightBase(value)
                p:setMaxWeight(value)
                -- the engine keeps TWO limits apart: maxWeight is the
                -- encumbrance threshold, and the body container has its own
                -- hard cap of 50 (constructor default, never changed by the
                -- character classes) past which picking up is refused. The
                -- stamp overrides that hard cap through the Aegis capacity
                -- hook, and it exists ONLY to lift it above 50 for big carry
                -- values. Stamping small values LOWERED the cap to the
                -- threshold itself and pickups died at the limit (community
                -- report), so below the vanilla cap the stamp goes away and
                -- vanilla overloading behaviour stays
                p:getModData().aegisCapacity = (value > 50) and value or nil
            end)
            if changed then
                Aegis.showToast(getText("UI_Aegis_CarryWeight") .. ": " .. tostring(value))
            end
        end
    elseif command == "spawnvehicle" then
        local ok = args and args.ok == true
        local name = args and args.name or ""
        Aegis.showToast((ok and getText("UI_Aegis_VehicleSpawned") or getText("UI_Aegis_VehicleFailed")) .. ": " .. tostring(name))
        if ok and args.id then
            AegisVehicleDetail.open(args.id)
        end
    elseif command == "spawnanimal" then
        local ok = args and args.ok == true
        local name = args and args.name or ""
        Aegis.showToast((ok and getText("UI_Aegis_AnimalSpawned") or getText("UI_Aegis_VehicleFailed")) .. ": " .. tostring(name))
    elseif command == "rightsSync" then
        if args and args.full then
            Aegis.rights = nil
        elseif args and args.none then
            Aegis.rights = false
        else
            local r = {}
            if args and type(args.rights) == "table" then
                for _, b in pairs(args.rights) do r[b] = true end
            end
            Aegis.rights = r
        end
        -- from now on "nil" really means confirmed full access instead of
        -- "no answer yet" (see AegisTheme.lua, Aegis.canSee)
        Aegis.rightsLoaded = true
        Aegis.role = args and args.role or nil
    elseif command == "banner" then
        -- translate only here: the dedicated server loads no UI texts,
        -- getText there returns just the raw key
        local text = args and args.text
        if args and args.key then
            text = args.par ~= nil and getText(args.key, args.par) or getText(args.key)
        end
        AegisBanner.show(text)
    elseif command == "hordeResult" then
        if args then
            Aegis.showToast("Horde: " .. tostring(args.spawned) .. "/" .. tostring(args.requested))
        end
    elseif command == "quitRelay" then
        -- the triggering admin restarts the server: /restart first
        --,
        -- if the server is still alive afterwards, /quit follows as safety net,
        -- the hoster panel brings the stopped server back up.
        -- every online client with QuitWorld answers, not just the admin who
        -- planned the restart: singling out the planner used to lock the
        -- restart to whether THAT ONE PERSON stayed online (community
        -- reports, three servers), any authorized admin is just as good
        -- the engine accepts /quit only from a connection whose role
        -- carries QuitWorld (measured on QuitCommand), so exactly that
        -- decides who answers. Wider than the old server area gate: every
        -- client the engine would listen to responds, and nobody the
        -- engine would refuse wastes the attempt
        local canQuit = false
        pcall(function()
            local level = tostring(getPlayer():getAccessLevel() or ""):lower()
            local role = AegisShared.roleForLevel(level)
            if role then
                canQuit = role:hasCapability(Capability.QuitWorld) == true
            else
                local r = getPlayer():getRole()
                canQuit = (r and r:hasCapability(Capability.QuitWorld)) == true
            end
        end)
        local responsible = args and args.anyone and canQuit
        if responsible and isClient() then
            -- the memo ages out: a restart planned later starts over with
            -- the polite /restart, only knocks of the SAME round skip it
            local fresh = AegisHud.relayRan and (getTimestampMs() - AegisHud.relayRan) < 300000
            if fresh then
                -- the server is knocking again, so it is still alive and
                -- /restart demonstrably did nothing. Straight to the command
                -- the engine really has, and never rearm the fallback: a
                -- repeat that pushes it forward keeps it from ever firing
                SendCommandToServer("/quit")
            else
                AegisHud.relayRan = getTimestampMs()
                SendCommandToServer("/restart")
                AegisHud.quitFallback = getTimestampMs() + 8000
            end
            -- trace to the actions log: which client actually picked the
            -- relay up. The server resends every minute while it lives,
            -- so repeated lines here mean the quit keeps failing
            pcall(function()
                sendClientCommand(getPlayer(), AegisShared.MODULE, "relayRan", {})
            end)
        end
    elseif command == "teleportVehicle" then
        local p = getPlayer()
        local x, y, z = args and args.x, args and args.y, (args and args.z) or 0
        if args and args.ok == true and args.phase == "exit" then
            -- first stage: teleport the player right away. In MP the
            -- vanilla teleport dismounts the admin cleanly and frees the
            -- vehicle, and arriving at the target streams the area in so
            -- the server watcher can pull the vehicle after him
            if x and y then
                if isClient() then
                    SendCommandToServer("/teleportto " .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
                elseif p then
                    -- solo: the in-process server part already dismounted
                    p:teleportTo(x, y, z + 0.0)
                end
            end
        elseif args and args.ok == true then
            -- the vehicle was recreated at the target: the old key is
            -- dead, a fresh one waits in the new glove box
            Aegis.showToast(getText("UI_Aegis_VehicleTeleportedKey"))
            -- a detail window still looking at the old id follows along
            pcall(function()
                local inst = AegisVehicleDetail.instance
                if inst and args.oldId and inst.vehicleId == args.oldId and args.newId then
                    inst:close()
                    AegisVehicleDetail.open(args.newId)
                end
            end)
        else
            Aegis.showToast(getText("UI_Aegis_VehicleFailed"))
        end
    elseif command == "denied" then
        local key = (args and args.reason == "capability") and "UI_Aegis_DeniedCap" or "UI_Aegis_Denied"
        Aegis.showToast(getText(key))
    end
end)

-- Aegis teleport on world map right click (key M). Vanilla only shows its
-- own menu in debug mode or as MP vanilla admin, with the teleport buried
-- between dev options; Aegis adds a clean entry everywhere else where
-- the user has Aegis access
local function patchWorldMap()
    if not ISWorldMap or ISWorldMap.aegisTeleport then return end
    ISWorldMap.aegisTeleport = true
    local prev = ISWorldMap.onRightMouseUp
    ISWorldMap.onRightMouseUp = function(self, x, y)
        local result = prev(self, x, y)
        -- where the vanilla menu appears, it already has the teleport itself
        if getDebug() or (isClient() and getAccessLevel() == "admin") then return result end
        if result == true then return result end
        local p = getPlayer()
        if not p or not Aegis.allowed(p) or not Aegis.canSee("world") then return result end
        local worldX = self.mapAPI:uiToWorldX(x, y)
        local worldY = self.mapAPI:uiToWorldY(x, y)
        if not getWorld():getMetaGrid():isValidChunk(worldX / 10, worldY / 10) then return result end
        local context = ISContextMenu.get(0, x + self:getAbsoluteX(), y + self:getAbsoluteY())
        context:addOption(getText("UI_Aegis_MapTeleport"), self, function(map)
            Aegis.teleportSmart(worldX, worldY, 0)
            Aegis.logAction("world", string.format("Map teleport to %d,%d", math.floor(worldX), math.floor(worldY)))
            -- close the map, otherwise you stand invisible behind the open map
            map:close()
        end)
        return result
    end
end

-- solo needs the admin role, otherwise the power setters do nothing;
-- plus the map patch
Events.OnGameStart.Add(function()
    -- every fresh session (including reconnect without client restart) starts
    -- unsynced, otherwise stale rights from the previous server connection
    -- could briefly carry over (see AegisTheme.lua)
    Aegis.rights = nil
    Aegis.rightsLoaded = false
    Aegis.role = nil
    Aegis.ensureSoloRole()
    patchWorldMap()
    -- heal characters that still carry the old small capacity stamp: it
    -- lowered the body hard cap below the vanilla 50 and blocked pickups
    -- at the carry limit. A player stamp at or under 50 is never right,
    -- the stamp only exists to raise the cap
    pcall(function()
        local p = getPlayer()
        local md = p and p:getModData()
        local s = md and tonumber(md.aegisCapacity)
        if s and s <= 50 then md.aegisCapacity = nil end
    end)
    -- fetch the rights right away instead of waiting for the first window
    -- open: entry points outside the window (vehicle context menu) are
    -- gated by canSee and stayed invisible until the panel was opened once
    if isClient() and Aegis.allowed(getPlayer()) then
        sendClientCommand(getPlayer(), AegisShared.MODULE, "rightsReq", {})
    end
end)

-- /setaccesslevel changes the level mid session and no aegis command
-- runs with it, so the rights cache kept the OLD verdict until the gold
-- panel was opened once. Until then every context menu entry gated by
-- canSee was missing, and a demoted admin kept entries he no longer had
--. This watches the level and
-- refetches on any change
local levelWatchNext = 0
local levelWatchLast = nil
-- The icon only appears once the server has confirmed at least one area
-- (see Aegis.hasAnyArea). That made a single lost or ill timed answer
-- enough to hide it for the rest of the session, and /setaccesslevel is
-- exactly where that happens: the client notices the new level within two
-- seconds and asks immediately, so the request can reach the server while
-- it still has the OLD level on record. The answer is then an honest "no
-- areas" for a moment that has already passed, and nothing ever asked
-- again. Found after a run of quick user/admin switches left the icon gone
-- for good. Retry while we believe we are staff and hold no area, capped
-- so a role that legitimately grants nothing does not ask forever
local rightsTries, rightsNextTry = 0, 0
local RIGHTS_MAX_TRIES = 5

-- Vanilla switches godmode, invisibility and noclip ON by itself whenever a
-- character gains an admin level, and it does so again after every
-- promotion, so a deliberate "off" kept coming back. The
-- engine sets them internally, there is no hook to stop the grant, so this
-- puts them back the way the admin left them. Runs on every watch tick, not
-- only on a level change, because the grant does not always coincide with
-- one. It never fights the admin: Aegis.powerIntent records what was left
-- standing after any toggle in our own panel, and only powers that came on
-- WITHOUT such a toggle are switched off again.
-- The full heal and the hunger/thirst reset that arrive with the same
-- promotion cannot be undone, there is no counterpart for them
local powerLastNote = nil

function AegisHud.enforcePowers(level)
    if AegisShared.featureOn("PlayerAutoAdminPowers") then return end
    if not AegisShared.levelIsAdmin(level) then return end
    local intent = Aegis.powerIntent or {}
    local turnedOff = {}
    local p = getPlayer()
    if p then
        if p:isGodMod() and not intent.god then
            p:setGodMod(false)
            table.insert(turnedOff, "godmode")
        end
        if p:isInvisible() and not intent.invisible then
            p:setInvisible(false)
            table.insert(turnedOff, "invisible")
        end
        if p:isNoClip() and not intent.noclip then
            p:setNoClip(false)
            table.insert(turnedOff, "noclip")
        end
    end
    -- a quiet pass clears the note, otherwise the dedup below swallows the
    -- NEXT occurrence of the same trio for good and the log silently
    -- under-reports. The watcher ticks every two seconds, so dropping the
    -- dedup entirely would write a line per tick while the state lasts:
    -- clearing on the quiet pass is the middle road. Found while reading
    -- this very log as evidence, where a later strip was missing from it
    if #turnedOff == 0 then
        powerLastNote = nil
        return
    end
    -- the off has to reach the server, the same packet the vanilla admin
    -- panel sends after a toggle. Without it the server keeps the powers
    -- on, hands them back on every login and overwrites any manual off
    -- with the next echo
    if p then Aegis.syncPowers(p) end
    local note = table.concat(turnedOff, ", ")
    if note ~= powerLastNote then
        powerLastNote = note
        print("[Aegis] automatic admin powers switched back off: " .. note)
    end
    Aegis.showToast(getText("UI_Aegis_AutoPowersOff"))
end

Events.OnTick.Add(function()
    if not isClient() then return end
    -- the level itself is read EVERY frame, not on the two second beat: the
    -- engine grants godmode, invisibility and noclip the instant a promotion
    -- arrives, and with the old throttle they stayed on for up to two full
    -- seconds before the change was even noticed: whoever hops to admin
    -- briefly to spawn something is a glowing ghost meanwhile. One java
    -- getter and a string compare per frame is nothing next to what a frame
    -- already costs. Everything heavier below keeps the throttle
    local level = nil
    pcall(function() level = tostring(getPlayer():getAccessLevel() or ""):lower() end)
    if level == nil then return end
    local now = getTimestampMs()
    if level ~= levelWatchLast then
        local first = levelWatchLast == nil
        levelWatchLast = level
        -- a real change refetches the rights, both paths strip the powers
        if not first then
            Aegis.rights = nil
            Aegis.rightsLoaded = false
            Aegis.role = nil
            -- a fresh level deserves a fresh set of attempts
            rightsTries, rightsNextTry = 0, now + 3000
            print("[Aegis] access level changed to '" .. level .. "', refetching rights")
            if Aegis.allowed(getPlayer()) then
                sendClientCommand(getPlayer(), AegisShared.MODULE, "rightsReq", {})
            end
            -- a promotion re-grants the powers, so the recorded intent from
            -- before the demotion is what counts again. This runs in the
            -- SAME frame as the detected change now
            AegisHud.enforcePowers(level)
        else
            -- the login grant lands before the first watch beat, so the
            -- session start is stripped in the same frame too
            AegisHud.enforcePowers(level)
        end
        return
    end
    if now < levelWatchNext then return end
    levelWatchNext = now + 2000
    AegisHud.enforcePowers(level)
    local p = getPlayer()
    if p and Aegis.allowed(p) and not Aegis.hasAnyArea() then
        if rightsTries < RIGHTS_MAX_TRIES and now >= rightsNextTry then
            rightsTries = rightsTries + 1
            rightsNextTry = now + 3000
            print("[Aegis] staff level '" .. level .. "' but no area granted, asking the server again ("
                .. rightsTries .. "/" .. RIGHTS_MAX_TRIES .. ")")
            sendClientCommand(p, AegisShared.MODULE, "rightsReq", {})
        end
    else
        rightsTries = 0
    end
end)

-- safety net for the restart relay: only kicks in if /restart did not
-- stop the server (this client is still running then)
Events.OnTick.Add(function()
    if AegisHud.quitFallback and getTimestampMs() >= AegisHud.quitFallback then
        AegisHud.quitFallback = nil
        if isClient() then
            SendCommandToServer("/quit")
        end
    end
end)
