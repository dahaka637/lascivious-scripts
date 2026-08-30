-- Picker for the recorded player statistics: which counters to clear, for
-- one player or for everyone, plus the full wipe of the ledger file.
require "Aegis/AegisTheme"

AegisStatsReset = ISPanel:derive("AegisStatsReset")

-- bestHours and bestKills describe the same run and are always cleared
-- together, a best life without its kill count says nothing
local FIELDS = {
    { key = "zkills",    fields = { "zkills" },                  label = "UI_AegisPlayer_ZombieKills" },
    { key = "deaths",    fields = { "deaths" },                  label = "UI_AegisPlayer_StatDeaths" },
    { key = "distM",     fields = { "distM" },                   label = "UI_AegisPlayer_StatDist" },
    { key = "best",      fields = { "bestHours", "bestKills" },  label = "UI_Aegis_StatsFieldBest", tip = "UI_Aegis_StatsFieldBestTip" },
    { key = "bandits",   fields = { "bandits" },                 label = "UI_AegisPlayer_StatBandits" },
    { key = "pvp",       fields = { "pvp" },                     label = "UI_Aegis_StatsFieldPvp" },
}

local ROW_H = 30
local PAD = 16

function AegisStatsReset.show(username)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel:new(0, 0, sw, sh)
    setmetatable(o, AegisStatsReset)
    AegisStatsReset.__index = AegisStatsReset
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.55 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.username = username
    o.picked = {}
    o.allPlayers = false

    o.cardW = 460
    o.lineH = Aegis.fontH(UIFont.Small)
    o.headH = 14 + Aegis.fontH(UIFont.Medium) + 8
    o.hint = Aegis.wrapText(getText("UI_Aegis_StatsResetHint"), UIFont.Small, o.cardW - 2 * PAD, 3)
    o.hintH = #o.hint * o.lineH + 10
    o.listTop = o.headH + o.hintH + ROW_H + 6
    o.cardH = o.listTop + #FIELDS * ROW_H + 12 + 36 + 12 + 36 + PAD

    o:initialise()
    o:addToUIManager()
    o:setAlwaysOnTop(true)

    local cx = math.floor((sw - o.cardW) / 2)
    local cy = math.floor((sh - o.cardH) / 2)
    local inner = o.cardW - 2 * PAD

    o.scope = AegisToggle:new(cx + PAD, cy + o.headH + o.hintH, inner, 26,
        getText("UI_Aegis_StatsScopeAll"), "players", o, function(panel, checked)
            panel.allPlayers = checked
        end)
    o:addChild(o.scope)

    o.rows = {}
    for i, def in ipairs(FIELDS) do
        local t = AegisToggle:new(cx + PAD, cy + o.listTop + (i - 1) * ROW_H, inner, 26,
            getText(def.label), nil, o, function(panel, checked)
                panel.picked[def.key] = checked or nil
            end)
        if def.tip then t.tooltip = getText(def.tip) end
        o:addChild(t)
        table.insert(o.rows, t)
    end

    local by = cy + o.cardH - PAD - 36 - 12 - 36
    local wipe = AegisButton:new(cx + PAD, by, inner, 36, getText("UI_Aegis_StatsWipe"), "ban", o, AegisStatsReset.onWipe)
    wipe.style = "danger"
    wipe.tooltip = getText("UI_Aegis_StatsWipeAsk")
    o:addChild(wipe)

    local bw = math.floor((inner - 12) / 2)
    o:addChild(AegisButton:new(cx + PAD, cy + o.cardH - PAD - 36, bw, 36,
        getText("UI_Aegis_Cancel"), nil, o, AegisStatsReset.onCancel))
    local apply = AegisButton:new(cx + PAD + bw + 12, cy + o.cardH - PAD - 36, bw, 36,
        getText("UI_Aegis_StatsReset"), "refresh", o, AegisStatsReset.onApply)
    apply.style = "danger"
    o:addChild(apply)
    return o
end

function AegisStatsReset:onCancel()
    self:removeFromUIManager()
end

function AegisStatsReset:collect()
    local out = {}
    for _, def in ipairs(FIELDS) do
        if self.picked[def.key] then
            for _, f in ipairs(def.fields) do table.insert(out, f) end
        end
    end
    return out
end

function AegisStatsReset:send(args)
    self:removeFromUIManager()
    sendClientCommand(getPlayer(), "AegisPlayer", "statsReset", args)
end

function AegisStatsReset:onApply()
    local fields = self:collect()
    if #fields == 0 then
        Aegis.showToast(getText("UI_Aegis_StatsPickNone"))
        return
    end
    local all = self.allPlayers
    local msg = all and getText("UI_Aegis_StatsResetAskAll")
        or getText("UI_Aegis_StatsResetAskOne", self.username)
    local panel = self
    AegisConfirm.show(getText("UI_Aegis_StatsReset"), msg, getText("UI_Aegis_StatsReset"), self, function()
        panel:send({ fields = fields, user = (not all) and panel.username or nil })
    end)
end

function AegisStatsReset:onWipe()
    local panel = self
    AegisConfirm.show(getText("UI_Aegis_StatsWipe"), getText("UI_Aegis_StatsWipeAsk"),
        getText("UI_Aegis_StatsWipe"), self, function()
            panel:send({ wipe = true })
        end)
end

function AegisStatsReset:prerender()
    ISPanel.prerender(self)
    local c = Aegis.col
    local cx = math.floor((self.width - self.cardW) / 2)
    local cy = math.floor((self.height - self.cardH) / 2)
    Aegis.shadow(self, cx, cy, self.cardW, self.cardH, 26, 0.7)
    Aegis.roundFrame(self, cx, cy, self.cardW, self.cardH, 12, 1, c.line, c.bg)
    Aegis.text(self, getText("UI_Aegis_StatsReset"), cx + PAD, cy + 14, UIFont.Medium, c.text)
    local ty = cy + self.headH
    for _, line in ipairs(self.hint) do
        Aegis.text(self, line, cx + PAD, ty, UIFont.Small, c.muted)
        ty = ty + self.lineH
    end
end

function AegisStatsReset:onMouseDown() return true end
