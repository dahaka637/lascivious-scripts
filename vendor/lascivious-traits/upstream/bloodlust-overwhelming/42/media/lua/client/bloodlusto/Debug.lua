local BloodlustTrait = require("bloodlusto/Registries").traits.Bloodlust
local Bloodiness = require('bloodlusto/Bloodiness')
local Bloodlust = require('bloodlusto/Bloodlust')

require "ISUI/ISPanel"


local SB = require('bloodlusto/Sandbox')
local MO = require('bloodlusto/Options')


local prev_x, prev_y = 10, 10
if BloodlustOverwhelmingDebugPanel then
    prev_x = BloodlustOverwhelmingDebugPanel:getX()
    prev_y = BloodlustOverwhelmingDebugPanel:getY()
    BloodlustOverwhelmingDebugPanel:close()
end


local FONT = UIFont.Small
local PADDING = 5

local DebugPanel = ISPanel:derive("DebugPanel")

function DebugPanel.setText(text)
    if not DebugPanel.instance then
        DebugPanel.instance = DebugPanel:new(prev_x, prev_y, 400, 200)
        DebugPanel.instance:initialise()
        DebugPanel.instance:addToUIManager()
        BloodlustOverwhelmingDebugPanel = DebugPanel.instance
    end
    DebugPanel.instance.text = text
    DebugPanel.instance:updateSize()
end

function DebugPanel:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.text = "None"
    o.backgroundColor = {r=0, g=0, b=0, a=0.5}
    o.moveWithMouse = true
    return o
end

function DebugPanel:updateSize()
    local max_width = 0
    local line_count = 0
    for _, line in ipairs(string.split(self.text, "\n")) do
        line_count = line_count + 1
        local width = getTextManager():MeasureStringX(FONT, line)
        if width > max_width then
            max_width = width
        end
    end
    self:setWidth(max_width + PADDING * 2)
    self:setHeight(line_count * getTextManager():getFontHeight(FONT) + PADDING * 2)
end


function DebugPanel:close()
    DebugPanel.instance = nil
    self:removeFromUIManager()
end

function DebugPanel:render()
    local y = PADDING
    local font_height = getTextManager():getFontHeight(FONT)
    for _, line in ipairs(string.split(self.text, "\n")) do
        self:drawText(line, PADDING, y, 1, 1, 1, 1, FONT)
        y = y + font_height
    end
end


--- @param player IsoPlayer
local function updateDebug(player)
    if player ~= getPlayer() then return end
    if not MO.debug or not player:hasTrait(BloodlustTrait) then
        if DebugPanel.instance then DebugPanel.instance:close() end
        return
    end
    local player_data = player:getModData()
    local mod_data = player_data.BloodlustO

    local text = "Bloodlust Overwhelming"

    -- Player data
    if mod_data then
        if mod_data.bloodlust then
            text = text..'\nBloodlust: '..tostring(math.floor(mod_data.bloodlust*100)/100)
        end
        if mod_data.frenzy_progress then
            text = text..'\nFrenzy Progress: '..tostring(math.floor(mod_data.frenzy_progress*100)/100)
        end
        if mod_data.buffered_exertion then
            text = text..'\nBuffered Exertion: '..tostring(math.floor(mod_data.buffered_exertion*100)/100)
        end
        if mod_data.frenzy_instakills then
            text = text..'\nFrenzy Instakills: '..tostring(math.floor(mod_data.frenzy_instakills*100)/100)
        end
        if mod_data.frenzy_instakills_decayed_in_sleep then
            text = text..'\nFrenzy Instakills (decayed in sleep): '..tostring(math.floor(mod_data.frenzy_instakills_decayed_in_sleep*100)/100)
        end
        if mod_data.distance_to_zombie then
            text = text..'\nDistance to closest zombie: '..tostring(math.floor(mod_data.distance_to_zombie*100)/100)
        end
    else
        text = text..'\nNone'
    end

    -- Instance
    local instance = Bloodlust.getInstance(player)

    if instance.control.outburst then
        text = text..'\n\nOutburst: '..instance.control.outburst
        if instance.control.outburst == "tracking" then
            local following = instance.control:testFollowing()
            if following and following ~= 'chance' then
                text = text..'\nFollowing: '..following
            else
                text = text..'\nFollowing: CAN OCCUR!'
            end
        end
    else
        local tracking = instance.control:testTracking()
        if tracking and tracking ~= 'chance' then
            text = text..'\n\nTracking: '..tracking
        else
            text = text..'\n\nTracking: CAN OCCUR!'
        end
    end

    if instance.in_combat then
        text = text..'\nIn combat!'
    end

    DebugPanel.setText(text)
end
Events.OnPlayerUpdate.Add(updateDebug)
