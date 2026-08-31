
local SECTION = PZAPI.ModOptions:create('BloodlustO_RedVision', 'Bloodlust: Red Vision')


SECTION:addDescription('Your whole screen goes red at high bloodlust.\nIt also happens to improve your ability to see in the dark.')

SECTION:addTickBox('enable', 'Enable Red Vision', true)


SECTION:addSlider('min_bloodlust', 'Min Bloodlust',
        0, 100, 1,
        50,
        'Bloodlust level at which Red Vision starts to show')
SECTION:addSlider('max_at_bloodlust', 'Max At Bloodlust',
        0, 100, 1,
        100,
        'Bloodlust level at which Red Vision is at maximum intensity')

SECTION:addSlider('min_frenzy_bloodlust', 'Min Bloodlust in Frenzy',
        0, 100, 1,
        0,
        'Bloodlust level at which Red Vision starts to show in frenzy')
SECTION:addSlider('max_at_frenzy_bloodlust', 'Max At Bloodlust in Frenzy',
        0, 100, 1,
        90,
        'Bloodlust level at which Red Vision is at maximum intensity in frenzy')


SECTION:addSlider('max_alpha', 'Max Alpha',
        0, 1, 0.05,
        0.3,
        'Red alpha at maximum intensity')


SECTION:addSeparator()


SECTION:addSlider('instakill_event_added_alpha', 'Instakill Added Alpha',
        0, 1, 0.01,
        0.15,
        'How much alpha to add when you instakill')
SECTION:addSlider('instakill_event_duration', 'Instakill Duration',
        10, 60000, 10,
        500,
        'How long alpha transitions back to normal after addition')

SECTION:addSlider('kill_event_added_alpha', 'Kill Added Alpha',
        0, 1, 0.01,
        0.1,
        'How much alpha to add when you kill')
SECTION:addSlider('kill_event_duration', 'Kill Duration',
        10, 60000, 10,
        250,
        'How long alpha transitions back to normal after addition')

SECTION:addSlider('hit_event_added_alpha', 'Hit Added Alpha',
        0, 1, 0.01,
        0.02,
        'How much alpha to add when you hit')
SECTION:addSlider('hit_event_duration', 'Hit Duration',
        10, 60000, 10,
        100,
        'How long alpha transitions back to normal after addition')

SECTION:addSlider('hurt_event_added_alpha', 'Hurt Added Alpha',
        0, 1, 0.01,
        0.5,
        'How much alpha to add when you get hit by a zombie')
SECTION:addSlider('hurt_event_duration', 'Hurt Duration',
        10, 60000, 10,
        3000,
        'How long alpha transitions back to normal after addition')

SECTION:addSlider('tracking_event_added_alpha', 'Hurt Added Alpha',
        0, 1, 0.01,
        0.3,
        'How much alpha to add when tracking outburst occurs\n(Duration is the same as movement lock duration)')



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
