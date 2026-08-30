-- Lascivious Scripts - Multiplayer Time Vote
-- Minimal transparent vote UI. The panel is presentation/input only; it never
-- owns, enforces or restores the simulation multiplier.

require "ISUI/ISPanel"
require "LasciviousScripts/TimeVote/Core"

local Core = LasciviousScripts.TimeVote

local ICON_SCALE = 0.50
local ICON_GAP = 4
local BUTTON_GAP = 7
local SUB_ROW_HEIGHT = 16
local MIN_BUTTON_WIDTH = 20

local ACTIVE_TINT = { r = 177 / 255, g = 151 / 255, b = 252 / 255, a = 1.0 }
local INACTIVE_TINT = { r = 0.55, g = 0.55, b = 0.55, a = 0.5 }
local VOTE_TINT = { r = 0.85, g = 0.85, b = 0.85, a = 0.85 }

local function font()
    return UIFont and UIFont.Small or nil
end

local SpeedButton = ISPanel:derive("LasciviousScriptsTimeVoteSpeedButton")

function SpeedButton:render()
    local iconX = math.floor((self.width - self.iconW) / 2)
    local tint = self.active and ACTIVE_TINT or INACTIVE_TINT
    self:drawTextureScaled(self.texture, iconX, 0, self.iconW, self.iconH, tint.a, tint.r, tint.g, tint.b)

    if not self.showVotes or not self.voteCount or self.voteCount <= 0 then return end

    local text = tostring(self.voteCount)
    local textW = 0
    local ok, measured = pcall(function() return getTextManager():MeasureStringX(font(), text) end)
    if ok and measured then textW = measured end

    -- Intention-of-vote icon intentionally stays at its original size.
    local userW = self.userTexture and self.userTexture:getWidth() or 0
    local userH = self.userTexture and self.userTexture:getHeight() or 0
    local subW = userW + (userW > 0 and 3 or 0) + textW
    local subX = math.floor((self.width - subW) / 2)
    local subY = self.iconH + ICON_GAP

    if self.userTexture then
        self:drawTextureScaled(self.userTexture, subX, subY + math.floor((SUB_ROW_HEIGHT - userH) / 2), userW, userH, VOTE_TINT.a, VOTE_TINT.r, VOTE_TINT.g, VOTE_TINT.b)
    end
    self:drawText(text, subX + userW + (userW > 0 and 3 or 0), subY, VOTE_TINT.r, VOTE_TINT.g, VOTE_TINT.b, VOTE_TINT.a, font())
end

function SpeedButton:onMouseUp(x, y)
    if self.onclick then self.onclick(self.level) end
    return true
end

function SpeedButton:setState(active, voteCount)
    self.active = active
    self.voteCount = voteCount or 0
end

function SpeedButton:new(texture, userTexture, level, showVotes, onclick)
    local iconW = math.max(1, math.floor(texture:getWidth() * ICON_SCALE + 0.5))
    local iconH = math.max(1, math.floor(texture:getHeight() * ICON_SCALE + 0.5))
    local buttonW = math.max(MIN_BUTTON_WIDTH, iconW)
    local o = ISPanel:new(0, 0, buttonW, iconH + ICON_GAP + SUB_ROW_HEIGHT)
    setmetatable(o, self)
    self.__index = self

    o.texture = texture
    o.iconW = iconW
    o.iconH = iconH
    o.userTexture = userTexture
    o.level = level
    o.showVotes = showVotes
    o.onclick = onclick
    o.active = false
    o.voteCount = 0
    o.moveWithMouse = false
    o.background = false
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }

    return o
end

local SpeedPanel = ISPanel:derive("LasciviousScriptsTimeVoteSpeedPanel")
LasciviousScripts.TimeVote.SpeedPanel = SpeedPanel

function SpeedPanel:layout()
    local x, maxH = 0, 0
    for _, button in ipairs(self.buttons) do
        button:setX(x)
        button:setY(0)
        x = x + button.width + BUTTON_GAP
        if button.height > maxH then maxH = button.height end
    end
    self:setWidth(math.max(1, x - BUTTON_GAP))
    self:setHeight(maxH)
end

function SpeedPanel:setData(votes, online, applied)
    local tally = {}
    for _, key in ipairs(online or {}) do
        local level = (votes and votes[key]) or Core.NORMAL
        tally[level] = (tally[level] or 0) + 1
    end

    for _, button in ipairs(self.buttons) do button:setState(button.level == applied, tally[button.level]) end
    self:layout()
end

function SpeedPanel:prerender()
    self:setX(getPlayerScreenWidth(0) - self.width - 14)
    local clock = UIManager.getClock and UIManager.getClock() or nil
    if clock and clock.isVisible and clock:isVisible() then self:setY(16 + clock:getHeight()) else self:setY(10) end

    if not self.childrenAdded then
        self.childrenAdded = true
        for _, button in ipairs(self.buttons) do self:addChild(button) end
    end

    ISPanel.prerender(self)
end

function SpeedPanel:new(onVote)
    local o = ISPanel:new(0, 0, 1, 1)
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = false
    o.childrenAdded = false

    local userTexture = getTexture("media/textures/tv_user.png")
    o.buttons = {
        SpeedButton:new(getTexture("media/textures/tv_speed_normal.png"), userTexture, Core.NORMAL, false, onVote),
        SpeedButton:new(getTexture("media/textures/tv_speed_fast.png"), userTexture, Core.NORMAL + 1, true, onVote),
        SpeedButton:new(getTexture("media/textures/tv_speed_veryfast.png"), userTexture, Core.NORMAL + 2, true, onVote),
        SpeedButton:new(getTexture("media/textures/tv_speed_wait.png"), userTexture, Core.NORMAL + 3, true, onVote),
    }

    o:layout()
    return o
end

return SpeedPanel
