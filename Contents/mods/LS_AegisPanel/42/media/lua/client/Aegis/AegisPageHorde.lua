-- Horde control: spawning and cleanup
require "Aegis/AegisWindow"

AegisPageHorde = ISPanel:derive("AegisPageHorde")

local MAX_SPAWN = 200

function AegisPageHorde.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPageHorde)
    AegisPageHorde.__index = AegisPageHorde
    o.background = false
    o.window = window
    o.colW = math.floor((w - 60) / 2)
    o.lastSpawn = 0
    return o
end

function AegisPageHorde:createChildren()
    local pad = 20
    local x = pad + 14
    local w = self.colW - 28

    -- spawn column left
    local y = pad + 66
    self.countSlider = AegisSlider:new(x, y, w, 24, self, nil)
    self.countSlider:setValues(1, MAX_SPAWN, 1, "")
    self.countSlider:setValue(25, true)
    self:addChild(self.countSlider)
    y = y + 52
    self.radiusSlider = AegisSlider:new(x, y, w, 24, self, nil)
    self.radiusSlider:setValues(1, 30, 1, "")
    self.radiusSlider:setValue(8, true)
    self:addChild(self.radiusSlider)
    y = y + 44
    self.crawlerToggle = AegisToggle:new(x, y, w, 28, getText("UI_Aegis_Crawlers"), "horde", self, nil)
    self:addChild(self.crawlerToggle)
    y = y + 34
    self.sprinterToggle = AegisToggle:new(x, y, w, 28, getText("UI_Aegis_Sprinters"), "bolt", self, nil)
    self:addChild(self.sprinterToggle)
    y = y + 34
    self.fireToggle = AegisToggle:new(x, y, w, 28, getText("UI_Aegis_OnFire"), "storm", self, nil)
    self:addChild(self.fireToggle)
    y = y + 34
    self.paratrooperToggle = AegisToggle:new(x, y, w, 28, getText("UI_Aegis_Paratrooper"), "heli", self, nil)
    self.paratrooperToggle.tooltip = getText("UI_Aegis_ParatrooperTooltip")
    self:addChild(self.paratrooperToggle)
    y = y + 52
    -- range is in floors, not raw Z units: the engine places the zombie
    -- at getZ()+heightOffset and lets it fall (bytecode verified); a value
    -- of 20-40 would be 20-40 floors up, far above any PZ building
    self.heightSlider = AegisSlider:new(x, y, w, 24, self, nil)
    self.heightSlider:setValues(1, 8, 1, "")
    self.heightSlider:setValue(4, true)
    self:addChild(self.heightSlider)
    y = y + 44
    self.spawnBtn = AegisButton:new(x, y, w, 40, getText("UI_Aegis_SpawnAtMe"), "horde", self, AegisPageHorde.onSpawn)
    self.spawnBtn.style = "gold"
    self:addChild(self.spawnBtn)
    self.spawnBottom = y + 40 + 20

    -- cleanup column right
    local ex = pad + self.colW + 20 + 14
    local ew = self.colW - 28
    local ey = pad + 66
    self.removeSlider = AegisSlider:new(ex, ey, ew, 24, self, nil)
    self.removeSlider:setValues(5, 100, 5, "")
    self.removeSlider:setValue(20, true)
    self:addChild(self.removeSlider)
    ey = ey + 44
    self.removeBtn = AegisButton:new(ex, ey, ew, 36, getText("UI_Aegis_Remove"), "trash", self, AegisPageHorde.onRemove)
    self:addChild(self.removeBtn)
    ey = ey + 44
    self.removeAllBtn = AegisButton:new(ex, ey, ew, 36, getText("UI_Aegis_RemoveAll"), "trash", self, AegisPageHorde.onRemoveAll)
    self.removeAllBtn.style = "danger"
    self:addChild(self.removeAllBtn)
    ey = ey + 44
    if isClient() then
        self.corpseBtn = AegisButton:new(ex, ey, ew, 36, getText("UI_Aegis_RemoveCorpses"), "trash", self, AegisPageHorde.onRemoveCorpses)
        self:addChild(self.corpseBtn)
        ey = ey + 44
    end
    self.removeBottom = ey + 12

    -- approach: horde walks in on the player from a distance
    local ay = self.removeBottom + 22
    self.approachY = ay
    self.distSlider = AegisSlider:new(ex, ay + 46, ew, 24, self, nil)
    self.distSlider:setValues(30, 150, 10, "")
    self.distSlider:setValue(60, true)
    self:addChild(self.distSlider)
    self.approachBtn = AegisButton:new(ex, ay + 82, ew, 38, getText("UI_Aegis_ApproachStart"), "bring", self, AegisPageHorde.onApproach)
    self.approachBtn.style = "gold"
    self:addChild(self.approachBtn)
    self.approachBottom = ay + 82 + 38 + 16
end

-- ------------------------------------------------------------------
-- Spawning
-- ------------------------------------------------------------------

-- one path for solo and MP: the Aegis server command spawns, sets sprinters and lures
function AegisPageHorde:sendHorde(dist)
    local p = getPlayer()
    if not p then return end
    sendClientCommand(p, "AegisAdmin", "horde", {
        x = math.floor(p:getX()),
        y = math.floor(p:getY()),
        z = math.floor(p:getZ()),
        count = math.min(self.countSlider.value, MAX_SPAWN),
        radius = self.radiusSlider.value,
        crawler = self.crawlerToggle.checked,
        onFire = self.fireToggle.checked,
        sprinter = self.sprinterToggle.checked,
        paratrooper = self.paratrooperToggle.checked,
        height = self.heightSlider.value,
        dist = dist,
    })
    self.lastSpawn = getTimestampMs()
end

function AegisPageHorde.onSpawn(self)
    self:sendHorde(nil)
end

function AegisPageHorde.onApproach(self)
    self:sendHorde(self.distSlider.value)
end

-- ------------------------------------------------------------------
-- Cleanup
-- ------------------------------------------------------------------

local function removeLoadedZombies(radius)
    -- loaded cells only, good enough for solo play
    local p = getPlayer()
    if not p then return end
    local px, py = p:getX(), p:getY()
    local list = getCell():getObjectListForLua()
    local doomed = {}
    for i = 0, list:size() - 1 do
        local obj = list:get(i)
        if instanceof(obj, "IsoZombie") then
            if not radius then
                table.insert(doomed, obj)
            else
                local dx = obj:getX() - px
                local dy = obj:getY() - py
                if dx * dx + dy * dy <= radius * radius then
                    table.insert(doomed, obj)
                end
            end
        end
    end
    for _, z in ipairs(doomed) do
        z:removeFromWorld()
        z:removeFromSquare()
    end
end

function AegisPageHorde.onRemove(self)
    local p = getPlayer()
    if not p then return end
    local radius = self.removeSlider.value
    if isClient() then
        SendCommandToServer(string.format("/removezombies -x %d -y %d -z %d -radius %d",
            math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ()), radius))
    else
        removeLoadedZombies(radius)
    end
    Aegis.logAction("horde", "Zombies removed (radius " .. radius .. ")")
end

function AegisPageHorde.onRemoveAll(self)
    if isClient() then
        SendCommandToServer("/removezombies -remove true")
    else
        removeLoadedZombies(nil)
    end
    Aegis.logAction("horde", "All zombies removed")
end

function AegisPageHorde.onRemoveCorpses(self)
    SendCommandToServer("/remove corpses")
    Aegis.logAction("horde", "Corpses removed")
end

-- ------------------------------------------------------------------
-- Frame
-- ------------------------------------------------------------------

function AegisPageHorde:prerender()
    if not self.approachBottom then return end
    local c = Aegis.col
    local pad = 20
    local x = pad + 14

    Aegis.roundFrame(self, pad, pad, self.colW, self.spawnBottom - pad, 10, 1, c.line, c.panel)
    Aegis.icon(self, "horde", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_Spawn"), pad + 36, pad + 10, UIFont.Medium, c.text)
    Aegis.text(self, getText("UI_Aegis_Count"), x, pad + 48, UIFont.Small, c.muted)
    Aegis.text(self, getText("UI_Aegis_Radius"), x, pad + 100, UIFont.Small, c.muted)
    if self.heightSlider then
        Aegis.text(self, getText("UI_Aegis_Height"), x, self.heightSlider.y - 18, UIFont.Small, c.muted)
    end

    local ex = pad + self.colW + 20
    Aegis.roundFrame(self, ex, pad, self.colW, self.removeBottom - pad, 10, 1, c.line, c.panel)
    Aegis.icon(self, "trash", ex + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_Remove"), ex + 36, pad + 10, UIFont.Medium, c.text)
    Aegis.text(self, getText("UI_Aegis_RemoveRadius"), ex + 14, pad + 48, UIFont.Small, c.muted)

    -- approach card
    Aegis.roundFrame(self, ex, self.approachY - 10, self.colW, self.approachBottom - self.approachY + 10, 10, 1, c.line, c.panel)
    Aegis.icon(self, "bring", ex + 14, self.approachY + 2, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_Approach"), ex + 36, self.approachY, UIFont.Medium, c.text)
    Aegis.text(self, getText("UI_Aegis_Distance"), ex + 14, self.approachY + 30, UIFont.Small, c.muted)

    -- brief feedback after spawning
    if self.lastSpawn > 0 and getTimestampMs() - self.lastSpawn < 2500 then
        Aegis.textRight(self, getText("UI_Aegis_Spawned"), pad + self.colW - 14, pad + 12, UIFont.Small, c.ok)
    end
end

-- ------------------------------------------------------------------
-- Paratrooper fall visual
-- ------------------------------------------------------------------

-- the server spawns paratroopers on the ground (authoritative) and
-- broadcasts their ids; each client lifts its LOCAL zombie copies and
-- lets the engine fall physics land them with the real landing anim.
-- Ids are kept pending for a moment: the zombie spawn packet can arrive
-- AFTER the command, so we re-scan until found or expired
local pendingDrops = {}

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" or command ~= "paraFx" then return end
    if not args or type(args.ids) ~= "table" then return end
    local wanted = {}
    for _, id in pairs(args.ids) do wanted[tonumber(id) or -999] = true end
    table.insert(pendingDrops, {
        ids = wanted,
        ground = tonumber(args.ground) or 0,
        height = math.min(8, math.max(1, tonumber(args.height) or 4)),
        deadline = getTimestampMs() + 5000,
        nextScan = 0,
    })
end)

Events.OnTick.Add(function()
    if #pendingDrops == 0 then return end
    local now = getTimestampMs()
    for i = #pendingDrops, 1, -1 do
        local drop = pendingDrops[i]
        if now >= drop.nextScan then
            drop.nextScan = now + 150
            local left = false
            pcall(function()
                local list = getCell():getObjectListForLua()
                for j = 0, list:size() - 1 do
                    local obj = list:get(j)
                    if instanceof(obj, "IsoZombie") and drop.ids[obj:getOnlineID()] then
                        drop.ids[obj:getOnlineID()] = nil
                        -- slight per-zombie spread so the group does not
                        -- land as one synchronized block
                        obj:setZ(drop.ground + drop.height + ZombRand(0, 100) / 100)
                        obj:setbFalling(true)
                    end
                end
                for _ in pairs(drop.ids) do left = true break end
            end)
            if not left or now > drop.deadline then
                table.remove(pendingDrops, i)
            end
        end
    end
end)

AegisWindow.registerPage({
    id = "horde",
    icon = "horde",
    label = "UI_Aegis_NavHorde",
    create = AegisPageHorde.create,
})
