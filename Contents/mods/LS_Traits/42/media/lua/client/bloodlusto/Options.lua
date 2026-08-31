
local function text(key)
    return getText('UI_BloodlustO_Options_'..key)
end

local SECTION = PZAPI.ModOptions:create('BloodlustO', text('Title'))

SECTION:addSlider('bloodiness_moodle_at', text('bloodiness_moodle_at'),
        0, 100, 1,
        30,
        text('bloodiness_moodle_at_tooltip'))

SECTION:addTickBox('bloodiness_exact', text('bloodiness_exact'), false,
        text('bloodiness_exact_tooltip'))

SECTION:addTickBox('debug', text('debug'), false,
        text('debug_tooltip'))

SECTION:addSeparator()

SECTION:addDescription(text('Phrases'))

SECTION:addTickBox('craving_instakill_phrase', text('craving_instakill_phrase'), true,
        text('craving_instakill_phrase_tooltip'))

SECTION:addTickBox('frenzy_instakill_phrase', text('frenzy_instakill_phrase'), true,
        text('frenzy_instakill_phrase_tooltip'))

SECTION:addTickBox('revenge_instakill_phrase', text('revenge_instakill_phrase'), true,
        text('revenge_instakill_phrase_tooltip'))

SECTION:addTickBox('frenzy_hurt_phrase', text('frenzy_hurt_phrase'), true,
        text('frenzy_hurt_phrase_tooltip'))

SECTION:addTickBox('pre_frenzy_phrase', text('pre_frenzy_phrase'), true,
        text('pre_frenzy_phrase_tooltip'))

SECTION:addTickBox('tracking_outburst_phrase', text('tracking_outburst_phrase'), true,
        text('tracking_outburst_phrase_tooltip'))




local MO = {}

SECTION.apply = function(self)
    for k,v in pairs(self.dict) do
        if v.type == "multipletickbox" then
            for i=1, #v.values do
                MO[(k.."_"..tostring(i))] = v:getValue(i)
            end
        elseif v.type == "button" then
            -- not a value
        else
            MO[k] = v:getValue()
        end
    end
end

Events.OnMainMenuEnter.Add(function() SECTION:apply() end)

SECTION:apply()

return MO
