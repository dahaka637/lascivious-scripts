local function text(key)
    return getText('UI_BloodlustO_RedVisionOptions_'..key)
end

local SECTION = PZAPI.ModOptions:create('BloodlustO_RedVision', text('Title'))


SECTION:addDescription(text('Description'))

SECTION:addTickBox('enable', text('enable'), true)


SECTION:addSlider('min_bloodlust', text('min_bloodlust'),
        0, 100, 1,
        50,
        text('min_bloodlust_tooltip'))
SECTION:addSlider('max_at_bloodlust', text('max_at_bloodlust'),
        0, 100, 1,
        100,
        text('max_at_bloodlust_tooltip'))

SECTION:addSlider('min_frenzy_bloodlust', text('min_frenzy_bloodlust'),
        0, 100, 1,
        0,
        text('min_frenzy_bloodlust_tooltip'))
SECTION:addSlider('max_at_frenzy_bloodlust', text('max_at_frenzy_bloodlust'),
        0, 100, 1,
        90,
        text('max_at_frenzy_bloodlust_tooltip'))


SECTION:addSlider('max_alpha', text('max_alpha'),
        0, 1, 0.05,
        0.3,
        text('max_alpha_tooltip'))


SECTION:addSeparator()


SECTION:addSlider('instakill_event_added_alpha', text('instakill_event_added_alpha'),
        0, 1, 0.01,
        0.15,
        text('instakill_event_added_alpha_tooltip'))
SECTION:addSlider('instakill_event_duration', text('instakill_event_duration'),
        10, 60000, 10,
        500,
        text('instakill_event_duration_tooltip'))

SECTION:addSlider('kill_event_added_alpha', text('kill_event_added_alpha'),
        0, 1, 0.01,
        0.1,
        text('kill_event_added_alpha_tooltip'))
SECTION:addSlider('kill_event_duration', text('kill_event_duration'),
        10, 60000, 10,
        250,
        text('kill_event_duration_tooltip'))

SECTION:addSlider('hit_event_added_alpha', text('hit_event_added_alpha'),
        0, 1, 0.01,
        0.02,
        text('hit_event_added_alpha_tooltip'))
SECTION:addSlider('hit_event_duration', text('hit_event_duration'),
        10, 60000, 10,
        100,
        text('hit_event_duration_tooltip'))

SECTION:addSlider('hurt_event_added_alpha', text('hurt_event_added_alpha'),
        0, 1, 0.01,
        0.5,
        text('hurt_event_added_alpha_tooltip'))
SECTION:addSlider('hurt_event_duration', text('hurt_event_duration'),
        10, 60000, 10,
        3000,
        text('hurt_event_duration_tooltip'))

SECTION:addSlider('tracking_event_added_alpha', text('tracking_event_added_alpha'),
        0, 1, 0.01,
        0.3,
        text('tracking_event_added_alpha_tooltip'))



local MO = {
    in_rate = 0.1,
    out_rate = 0.05,
    event_peak = 0.05,
    tracking_event_peak = 0.60
}

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
