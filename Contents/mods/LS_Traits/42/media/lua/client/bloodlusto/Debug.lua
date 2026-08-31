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
local function uiText(key)
    return getText('UI_BloodlustO_Debug_'..key)
end

local function reasonText(reason)
    if not reason then return "" end
    local key = 'UI_BloodlustO_Debug_Reason_'..tostring(reason):gsub("[^%w_]", "_")
    local value = getText(key)
    if value and value ~= key then
        return value
    end
    return tostring(reason)
end

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
    o.text = uiText("None")
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

    local debugText = uiText("Title")

    -- Player data
    if mod_data then
        if mod_data.bloodlust then
            debugText = debugText..'\n'..uiText("Bloodlust")..': '..tostring(math.floor(mod_data.bloodlust*100)/100)
        end
        if mod_data.frenzy_progress then
            debugText = debugText..'\n'..uiText("FrenzyProgress")..': '..tostring(math.floor(mod_data.frenzy_progress*100)/100)
        end
        if mod_data.buffered_exertion then
            debugText = debugText..'\n'..uiText("BufferedExertion")..': '..tostring(math.floor(mod_data.buffered_exertion*100)/100)
        end
        if mod_data.frenzy_instakills then
            debugText = debugText..'\n'..uiText("FrenzyInstakills")..': '..tostring(math.floor(mod_data.frenzy_instakills*100)/100)
        end
        if mod_data.frenzy_instakills_decayed_in_sleep then
            debugText = debugText..'\n'..uiText("FrenzyInstakillsDecayedInSleep")..': '..tostring(math.floor(mod_data.frenzy_instakills_decayed_in_sleep*100)/100)
        end
        if mod_data.distance_to_zombie then
            debugText = debugText..'\n'..uiText("DistanceToClosestZombie")..': '..tostring(math.floor(mod_data.distance_to_zombie*100)/100)
        end
    else
        debugText = debugText..'\n'..uiText("None")
    end

    -- Instance
    local instance = Bloodlust.getInstance(player)

    if instance.control.outburst then
        debugText = debugText..'\n\n'..uiText("Outburst")..': '..reasonText(instance.control.outburst)
        if instance.control.outburst == "tracking" then
            local following = instance.control:testFollowing()
            if following and following ~= 'chance' then
                debugText = debugText..'\n'..uiText("Following")..': '..reasonText(following)
            else
                debugText = debugText..'\n'..uiText("Following")..': '..uiText("CanOccur")
            end
        end
    else
        local tracking = instance.control:testTracking()
        if tracking and tracking ~= 'chance' then
            debugText = debugText..'\n\n'..uiText("Tracking")..': '..reasonText(tracking)
        else
            debugText = debugText..'\n\n'..uiText("Tracking")..': '..uiText("CanOccur")
        end
    end

    if instance.in_combat then
        debugText = debugText..'\n'..uiText("InCombat")
    end

    DebugPanel.setText(debugText)
end
Events.OnPlayerUpdate.Add(updateDebug)
