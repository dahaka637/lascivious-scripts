-- All vanilla admin powers (23), categorized and scrollable
require "Aegis/AegisWindow"
require "ISUI/ISLabel"
require "Entity/ISUI/CraftRecipe/ISRecipeScrollingListBox"
require "Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl"

AegisPagePowers = ISPanel:derive("AegisPagePowers")

-- hand crafting has no vanilla cheat flag: the build cheat frees building,
-- but the craft button stays wired to HandcraftLogic and keeps demanding
-- materials and the right workstation. Vanilla ships the lever anyway, as
-- its debug Force button: startHandcraft(true) performs a recipe regardless
-- of knowledge, skills and materials. The toggle reuses exactly that path
AegisCraftCheat = false

local prevCraftable = ISRecipeScrollingListBox.isCraftable
function ISRecipeScrollingListBox:isCraftable(recipe)
    if AegisCraftCheat then return true end
    return prevCraftable(self, recipe)
end

local prevStartCraft = ISWidgetHandCraftControl.startHandcraft
function ISWidgetHandCraftControl:startHandcraft(force)
    return prevStartCraft(self, force == true or AegisCraftCheat)
end

local prevCraftPrerender = ISWidgetHandCraftControl.prerender
function ISWidgetHandCraftControl:prerender()
    prevCraftPrerender(self)
    if AegisCraftCheat and self.buttonCraft and self.logic then
        -- free the button, but never mid craft (the original disables it
        -- while the timed action runs, that stays)
        local busy = self.logic:isCraftActionInProgress()
        if not busy then self.buttonCraft.enable = true end
    end
end

-- exact vanilla pattern from ISAdminPowerUI.lua (getters/setters + Lua statics taken 1:1)
local GROUPS = {
    {
        title = "UI_Aegis_GroupSurvival",
        powers = {
            -- master switch for the own head tag. The engine derives the
            -- SENT tag bit from the active powers alone, this flag stays
            -- local; hiding for everyone runs through the server hide
            -- list and the guard in AegisRoleTag. The pin in AegisTheme
            -- keeps the flag down between ticks, off never happens by
            -- itself, only through this switch
            { key = "AdminTag", label = "UI_Aegis_PowerAdminTag", icon = "crown", cap = "ToggleWriteRoleNameAbove",
              get = function(p) return p:isShowAdminTag() end,
              set = function(p, v)
                  Aegis.tagManualOff = not v
                  Aegis.setPref("tagOff", v and "0" or "1")
                  p:setShowAdminTag(v)
                  if isClient() then
                      sendClientCommand(p, AegisShared.MODULE, "tagHide", { on = not v })
                  end
              end },
            -- pure client visual, no engine capability involved (cap nil)
            { key = "NightVision", label = "UI_Aegis_PowerNightVision", icon = "fog",
              get = function(p) return Aegis.nightVision == true end,
              set = function(p, v) Aegis.setNightVision(v) end },
            { key = "GodMod", label = "UI_Aegis_PowerGod", icon = "shield", cap = "ToggleGodModHimself",
              get = function(p) return p:isGodMod() end, set = function(p, v) p:setGodMod(v) end },
            { key = "Invisible", label = "UI_Aegis_PowerInvisible", icon = "eye", cap = "ToggleInvisibleHimself",
              get = function(p) return p:isInvisible() end, set = function(p, v) p:setInvisible(v) end },
            { key = "NoClip", label = "UI_Aegis_PowerNoClip", icon = "noclip", cap = "ToggleNoclipHimself",
              get = function(p) return p:isNoClip() end, set = function(p, v) p:setNoClip(v) end },
            { key = "FastMove", label = "UI_Aegis_PowerFastMove", icon = "chevron", cap = "UseFastMoveCheat",
              get = function(p) return ISFastTeleportMove.cheat end,
              set = function(p, v) ISFastTeleportMove.cheat = v; p:setFastMoveCheat(v) end },
            { key = "TimedActionInstant", label = "UI_Aegis_PowerInstant", icon = "bolt", cap = "UseTimedActionInstantCheat",
              get = function(p) return p:isTimedActionInstantCheat() end, set = function(p, v) p:setTimedActionInstantCheat(v) end },
            { key = "UnlimitedCarry", label = "UI_Aegis_PowerCarry", icon = "items", cap = "ToggleUnlimitedCarry",
              get = function(p) return p:isUnlimitedCarry() end, set = function(p, v) p:setUnlimitedCarry(v) end },
            { key = "UnlimitedEndurance", label = "UI_Aegis_PowerEndurance", icon = "refresh", cap = "ToggleUnlimitedEndurance",
              get = function(p) return p:isUnlimitedEndurance() end, set = function(p, v) p:setUnlimitedEndurance(v) end },
        },
    },
    {
        title = "UI_Aegis_GroupCombat",
        powers = {
            { key = "UnlimitedAmmo", label = "UI_Aegis_PowerAmmo", icon = "plus", cap = "ToggleUnlimitedAmmo",
              get = function(p) return p:isUnlimitedAmmo() end, set = function(p, v) p:setUnlimitedAmmo(v) end },
            { key = "ZombiesDontAttack", label = "UI_Aegis_PowerZombiesPassive", icon = "horde", cap = "ManipulateZombie",
              get = function(p) return p:isZombiesDontAttack() end, set = function(p, v) p:setZombiesDontAttack(v) end },
            { key = "CanSeeAll", label = "UI_Aegis_PowerSeeAll", icon = "search", cap = "CanSeeAll",
              get = function(p) return p:canSeeAll() end, set = function(p, v) p:setCanSeeAll(v) end },
            { key = "CanHearAll", label = "UI_Aegis_PowerHearAll", icon = "speaker", cap = "CanHearAll",
              get = function(p) return p:canHearAll() end, set = function(p, v) p:setCanHearAll(v) end },
        },
    },
    {
        title = "UI_Aegis_GroupCrafting",
        powers = {
            { key = "KnowAllRecipes", label = "UI_Aegis_PowerRecipes", icon = "wand", cap = "ToggleKnowAllRecipes",
              get = function(p) return p:isKnowAllRecipes() end, set = function(p, v) p:setKnowAllRecipes(v) end },
            { key = "BuildCheat", label = "UI_Aegis_PowerBuild", icon = "home", cap = "UseBuildCheat",
              get = function(p) return ISBuildMenu.cheat end,
              set = function(p, v) ISBuildMenu.cheat = v; p:setBuildCheat(v) end },
            -- same trust level as the build cheat, hence the same capability.
            -- Deliberately NOT coupled to setKnowAllRecipes: the toggle
            -- above covers that on its own, and the coupling silently
            -- killed it on the way out. Without it the list
            -- shows known recipes only, the force path still crafts free
            { key = "CraftCheat", label = "UI_Aegis_PowerCraft", icon = "dot", cap = "UseBuildCheat",
              get = function(p) return AegisCraftCheat end,
              set = function(p, v) AegisCraftCheat = v end },
            { key = "FarmingCheat", label = "UI_Aegis_PowerFarming", icon = "dot", cap = "UseFarmingCheat",
              get = function(p) return ISFarmingMenu.cheat end,
              set = function(p, v) ISFarmingMenu.cheat = v; p:setFarmingCheat(v) end },
            { key = "FishingCheat", label = "UI_Aegis_PowerFishing", icon = "dot", cap = "UseFishingCheat",
              get = function(p) return p:isFishingCheat() end, set = function(p, v) p:setFishingCheat(v) end },
            { key = "MechanicsCheat", label = "UI_Aegis_PowerMechanics", icon = "gear", cap = "UseMechanicsCheat",
              get = function(p) return ISVehicleMechanics.cheat end,
              set = function(p, v) ISVehicleMechanics.cheat = v; p:setMechanicsCheat(v) end },
            { key = "MoveableCheat", label = "UI_Aegis_PowerMoveable", icon = "dot", cap = "UseMovablesCheat",
              get = function(p) return ISMoveableDefinitions.cheat end,
              set = function(p, v) ISMoveableDefinitions.cheat = v; p:setMovablesCheat(v) end },
        },
    },
    {
        title = "UI_Aegis_GroupTools",
        powers = {
            { key = "HealthCheat", label = "UI_Aegis_PowerHealthCheat", icon = "heal", cap = "UseHealthCheat",
              get = function(p) return ISHealthPanel.cheat end,
              set = function(p, v) ISHealthPanel.cheat = v; p:setHealthCheat(v) end },
            { key = "BrushTool", label = "UI_Aegis_PowerBrush", icon = "world", cap = "UseBrushToolManager",
              get = function(p) return BrushToolManager.cheat end,
              set = function(p, v) BrushToolManager.cheat = v; p:setCanUseBrushTool(v) end },
            { key = "LootZed", label = "UI_Aegis_PowerLootZed", icon = "dot", cap = "UseLootZed",
              get = function(p) return ISLootZed.cheat end,
              set = function(p, v) ISLootZed.cheat = v; p:setCanUseLootZed(v) end },
            { key = "LootLog", label = "UI_Aegis_PowerLootLog", icon = "dot", cap = "UseLootLog",
              get = function(p) return ISLootLog.cheat end,
              set = function(p, v) ISLootLog.cheat = v; p:setCanUseLootLog(v) end },
            { key = "AnimalCheat", label = "UI_Aegis_PowerAnimal", icon = "dot", cap = "AnimalCheats",
              get = function(p) return AnimalContextMenu.cheat end,
              set = function(p, v) AnimalContextMenu.cheat = v; p:setAnimalCheat(v) end },
            { key = "AnimalExtraValues", label = "UI_Aegis_PowerAnimalExtra", icon = "dot", cap = "AnimalCheats",
              get = function(p) return p:isAnimalExtraValuesCheat() end, set = function(p, v) p:setAnimalExtraValuesCheat(v) end },
        },
    },
}

local ROW_H = 32
local COLS = 2

function AegisPagePowers.create(window, x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, AegisPagePowers)
    AegisPagePowers.__index = AegisPagePowers
    o.background = false
    o.window = window
    o.toggles = {}
    o.groupTops = {}
    o.refreshTick = 0
    return o
end

function AegisPagePowers:createChildren()
    local pad = 20
    local innerX = pad + 14
    local innerW = self.width - innerX * 2
    local topBarH = 42

    -- Spectator: the free-cam combo in one switch (god, invisible,
    -- through walls, fast); the Lua API offers no truly detached
    -- camera, this is the agreed simulated approach.
    -- Right of the all-off button, page title sits on the left
    self.ghostToggle = AegisToggle:new(innerX + innerW - 150 - 12 - 170, pad + 6, 170, 28, getText("UI_Aegis_GhostMode"), "ghost", self, AegisPagePowers.onGhost)
    self.ghostToggle.tooltip = getText("UI_Aegis_GhostModeTooltip")
    self:addChild(self.ghostToggle)

    self.allOffBtn = AegisButton:new(innerX + innerW - 150, pad + 6, 150, 28, getText("UI_Aegis_PowersAllOff"), "ban", self, AegisPagePowers.onAllOff)
    self:addChild(self.allOffBtn)

    self.scroll = AegisScrollArea:new(innerX, pad + topBarH, innerW, self.height - pad * 2 - topBarH - 6)
    self:addChild(self.scroll)

    local colW = math.floor((self.scroll.width - 12 - 16) / COLS)
    local gap = 12
    local sy = 6

    for _, group in ipairs(GROUPS) do
        self.groupTops[group] = sy
        local header = ISLabel:new(2, sy, 22, getText(group.title), Aegis.col.goldHi.r, Aegis.col.goldHi.g, Aegis.col.goldHi.b, 1, UIFont.Medium, true)
        self.scroll:addChild(header)
        sy = sy + 28

        for i, def in ipairs(group.powers) do
            local col = (i - 1) % COLS
            local row = math.floor((i - 1) / COLS)
            local t = AegisToggle:new(2 + col * (colW + gap), sy + row * ROW_H, colW - gap, ROW_H - 4, getText(def.label), def.icon, self, AegisPagePowers.onPower)
            t.powerDef = def
            -- official vanilla tooltip text, same language/translation as the real cheat panel
            t.tooltip = getTextOrNull("IGUI_CheatPanel_" .. def.key .. "_tooltip")
            self.scroll:addChild(t)
            self.toggles[def.key] = t
        end
        local rows = math.ceil(#group.powers / COLS)
        sy = sy + rows * ROW_H + 18
    end

    self.scroll:setScrollHeight(sy)
    self:refreshToggles()
end

local GHOST_POWERS = { "GodMod", "Invisible", "NoClip", "FastMove" }

function AegisPagePowers:refreshToggles()
    local p = getPlayer()
    if not p then return end
    for _, group in ipairs(GROUPS) do
        for _, def in ipairs(group.powers) do
            local t = self.toggles[def.key]
            local ok, v = pcall(def.get, p)
            if ok then t:setChecked(v) end
            t:setEnabled(def.cap == nil or Aegis.hasCap(def.cap))
        end
    end
    if self.ghostToggle then
        local allOn = true
        for _, key in ipairs(GHOST_POWERS) do
            local t = self.toggles[key]
            if not t or not t.checked then allOn = false break end
        end
        self.ghostToggle:setChecked(allOn)
    end
end

function AegisPagePowers.onGhost(self, checked)
    local p = getPlayer()
    if not p then return end
    Aegis.ensureSoloRole()
    for _, key in ipairs(GHOST_POWERS) do
        local t = self.toggles[key]
        if t and t.enabled then
            pcall(t.powerDef.set, p, checked)
        end
    end
    Aegis.syncPowers(p)
    self:refreshToggles()
    Aegis.logAction("powers", checked and "Ghost mode enabled" or "Ghost mode disabled")
end

-- Client-only Java cheat setters run without a server roundtrip;
-- without this relay the log would never show which power was used.
-- No isClient gate: the loopback also fires in singleplayer
local function logAction(text)
    Aegis.logAction("powers", text)
end

function AegisPagePowers.onPower(self, checked, toggle)
    local p = getPlayer()
    if not p then return end
    Aegis.ensureSoloRole()
    local ok = pcall(toggle.powerDef.set, p, checked)
    if not ok then
        toggle:setChecked(not checked)
        return
    end
    Aegis.syncPowers(p)
    logAction((checked and "Power enabled: " or "Power disabled: ") .. getText(toggle.powerDef.label))
end

function AegisPagePowers.onAllOff(self)
    local p = getPlayer()
    if not p then return end
    local disabledList = {}
    for _, t in pairs(self.toggles) do
        if t.checked and t.enabled then
            pcall(t.powerDef.set, p, false)
            t:setChecked(false)
            table.insert(disabledList, getText(t.powerDef.label))
        end
    end
    Aegis.syncPowers(p)
    if #disabledList > 0 then
        logAction("All powers off: " .. table.concat(disabledList, ", "))
    end
end

function AegisPagePowers:onShow()
    self:refreshToggles()
end

function AegisPagePowers:update()
    ISPanel.update(self)
    self.refreshTick = self.refreshTick + 1
    if self.refreshTick >= 30 then
        self.refreshTick = 0
        self:refreshToggles()
    end
end

function AegisPagePowers:prerender()
    local c = Aegis.col
    local pad = 20
    Aegis.roundFrame(self, pad, pad, self.width - pad * 2, self.height - pad * 2, 10, 1, c.line, c.panel)
    Aegis.icon(self, "wand", pad + 14, pad + 12, 15, 1, c.gold)
    Aegis.text(self, getText("UI_Aegis_NavPowers"), pad + 36, pad + 10, UIFont.Medium, c.text)
end

AegisWindow.registerPage({
    id = "powers",
    icon = "wand",
    label = "UI_Aegis_NavPowers",
    create = AegisPagePowers.create,
})
