
local SECTION = PZAPI.ModOptions:create('BloodlustO_IntrusiveThoughts', 'Bloodlust: Intrusive Thoughts')


SECTION:addDescription('Relevant thoughts appear all throughout your screen at high bloodlust.\nThey alert you of rear danger and slightly move towards closest zombie.')

SECTION:addTickBox('enable', 'Enable Intrusive Thoughts', true)


SECTION:addSlider('min_bloodlust', 'Min Bloodlust',
        0, 100, 1,
        60,
        'Bloodlust level at which Intrusive Thoughts start to show')
SECTION:addSlider('max_at_bloodlust', 'Max At Bloodlust',
        0, 100, 1,
        100,
        'Bloodlust level at which Intrusive Thoughts are at maximum intensity')

SECTION:addSlider('min_frenzy_bloodlust', 'Min Bloodlust in Frenzy',
        0, 100, 1,
        0,
        'Bloodlust level at which Intrusive Thoughts start to show in frenzy')
SECTION:addSlider('max_at_frenzy_bloodlust', 'Max At Bloodlust in Frenzy',
        0, 100, 1,
        90,
        'Bloodlust level at which Intrusive Thoughts are at maximum intensity in frenzy')


SECTION:addSeparator()


SECTION:addSlider('max_elements', 'Max Thoughts',
        1, 1000, 1,
        16,
        'How many thoughts appear on screen at maximum intensity')
SECTION:addSlider('min_element_time', 'Min Thought Time (ms)',
        50, 60000, 50,
        500,
        'Minimum time a single thought stays on screen')
SECTION:addSlider('max_element_time', 'Max Thought Time (ms)',
        50, 60000, 50,
        3000,
        'Maximum time a single thought stays on screen')

SECTION:addSlider('max_alpha', 'Max Alpha',
        0, 1, 0.1,
        0.9,
        'Thoughts alpha at maximum intensity')
SECTION:addSlider('min_zoom', 'Min Size',
        0.1, 10, 0.1,
        0.8,
        'Thoughts size at minimum intensity')
SECTION:addSlider('max_zoom', 'Max Size',
        0.1, 10, 0.1,
        2,
        'Thoughts size at maximum intensity')

SECTION:addSlider('max_shake', 'Shaking (px)',
        0, 10, 1,
        1,
        'How much thoughts shake at maximum intensity')
SECTION:addSlider('max_zoom_flicker', 'Size Flicker',
        0, 10, 0.1,
        0.1,
        'How much thoughts size changes randomly at maximum intensity')
SECTION:addSlider('max_color_flicker', 'Color Flicker',
        0, 1, 0.01,
        0.07, -- 20/255
        'How much thoughts color changes randomly at maximum intensity')

SECTION:addSlider('max_text_corruption', 'Text Corruption',
        0, 1, 0.1,
        0.9,
        'Intensity of text corruption at maximum thoughts intensity')
SECTION:addSlider('max_text_corruption_interval', 'Text Corruption Max Interval (ms)',
        0, 60000, 50,
        250,
        'Text corruption interval at maximum thoughts intensity')
SECTION:addSlider('min_text_corruption_interval', 'Text Corruption Min Interval (ms)',
        0, 60000, 50,
        50,
        'Text corruption interval at minimum thoughts intensity')


SECTION:addSeparator()


SECTION:addSlider('max_zombie_tiles', 'Max Zombie Tiles',
        0, 1000, 1,
        6,
        'Tiles to zombie to trigger zombie-related thoughts')
SECTION:addSlider('min_zombie_tiles', 'Min Zombie Tiles',
        0, 1000, 1,
        2,
        'Tiles to zombie for maximum intensity of zombie-related thoughts')

SECTION:addSlider('zombie_close_added_elements', 'Zombie Added Thoughts',
        0, 1000, 1,
        4,
        'How many more thoughts appear when a zombie is at minimum distance')
SECTION:addSlider('zombie_close_added_alpha', 'Zombie Added Alpha',
        0, 1, 0.05,
        0.25,
        'How much less transparent thoughts are when a zombie is at minimum distance')
SECTION:addSlider('zombie_close_added_zoom', 'Zombie Added Size',
        0, 100, 1,
        1,
        'How much bigger thoughts are when a zombie is at minimum distance')
SECTION:addSlider('zombie_close_added_shake', 'Zombie Added Shake',
        0, 100, 1,
        2,
        'How much more thoughts shake when a zombie is at minimum distance')
SECTION:addSlider('zombie_close_min_text_corruption', 'Zombie Min Text Corruption',
        0, 1, 0.05,
        0.25,
        'Text corruption intensity when a zombie is at minimum distance')


SECTION:addSeparator()


SECTION:addSlider('min_event_responsiveness', 'Min Event Responsiveness',
        0, 1, 0.1,
        0.6,
        'How much event-added properties can affect thoughts\n(Each thought responsiveness is randomly selected between min and 1.0)')

SECTION:addSlider('hurt_thoughts_duration', 'Hurt Thoughts Duration (ms)',
        50, 60000, 50,
        10000,
        'For how long to show hurt thoughts when you get hit by a zombie')
SECTION:addSlider('hurt_add_duration', 'Hurt Add Duration (ms)',
        50, 60000, 50,
        4000,
        'Time it takes for thoughts properties to return back to normal after you get hit by a zombie')
SECTION:addSlider('hurt_added_alpha', 'Hurt Added Alpha',
        0, 1, 0.1,
        0.5,
        'Alpha to add when you get hit by a zombie')
SECTION:addSlider('hurt_added_zoom', 'Hurt Added Size',
        0, 10, 0.1,
        3,
        'How much bigger thoughts are when you get hit by a zombie')
SECTION:addSlider('hurt_added_red', 'Hurt Added Red',
        0, 1, 0.01,
        0.4, -- 100/255
        'How much redder thoughts are when you get hit by a zombie')
SECTION:addSlider('hurt_added_elements', 'Hurt Added Thoughts',
        0, 100, 1,
        5,
        'How many thoughts are added when you get hit by a zombie')

SECTION:addSlider('kill_thoughts_duration', 'Kill Thoughts Duration (ms)',
        50, 60000, 50,
        10000,
        'For how long to show kill thoughts when you kill')
SECTION:addSlider('kill_add_duration', 'Kill Add Duration (ms)',
        50, 60000, 50,
        3000,
        'Time it takes for thoughts properties to return back to normal after you kill')
SECTION:addSlider('kill_added_alpha', 'Kill Added Alpha',
        0, 1, 0.1,
        0.5,
        'Alpha to add when you kill')
SECTION:addSlider('kill_added_zoom', 'Kill Added Size',
        0, 10, 0.1,
        1,
        'How much bigger thoughts are when you kill')
SECTION:addSlider('kill_added_red', 'Kill Added Red',
        0, 1, 0.01,
        0.31, -- 80/255
        'How much redder thoughts are when you kill')
SECTION:addSlider('kill_added_elements', 'Kill Added Thoughts',
        0, 100, 1,
        10,
        'How many thoughts are added when you kill')

SECTION:addSlider('instakill_thoughts_duration', 'Instakill Thoughts Duration (ms)',
        50, 60000, 50,
        10000,
        'For how long to show instakill thoughts when you instakill')
SECTION:addSlider('instakill_add_duration', 'Instakill Add Duration (ms)',
        50, 60000, 50,
        3000,
        'Time it takes for thoughts properties to return back to normal after you instakill')
SECTION:addSlider('instakill_added_alpha', 'Instakill Added Alpha',
        0, 1, 0.1,
        0.5,
        'Alpha to add when you instakill')
SECTION:addSlider('instakill_added_zoom', 'Instakill Added Size',
        0, 10, 0.1,
        2,
        'How much bigger thoughts are when you instakill')
SECTION:addSlider('instakill_added_red', 'Instakill Added Red',
        0, 1, 0.01,
        0.58, -- 150/255
        'How much redder thoughts are when you instakill')
SECTION:addSlider('instakill_added_elements', 'Instakill Added Thoughts',
        0, 100, 1,
        20,
        'How many thoughts are added when you instakill')

SECTION:addSlider('hit_thoughts_duration', 'Hit Thoughts Duration (ms)',
        50, 60000, 50,
        3000,
        'For how long to show hit thoughts when you hit without killing')
SECTION:addSlider('hit_add_duration', 'Hit Add Duration (ms)',
        50, 60000, 50,
        500,
        'Time it takes for thoughts properties to return back to normal after you hit without killing')
SECTION:addSlider('hit_added_alpha', 'Hit Added Alpha',
        0, 1, 0.1,
        0.2,
        'Alpha to add when you hit without killing')
SECTION:addSlider('hit_added_zoom', 'Hit Added Size',
        0, 10, 0.1,
        0.5,
        'How much bigger thoughts are when you hit without killing')
SECTION:addSlider('hit_added_red', 'Hit Added Red',
        0, 1, 0.01,
        0.19, -- 50/255
        'How much redder thoughts are when you hit without killing')
SECTION:addSlider('hit_added_elements', 'Hit Added Thoughts',
        0, 100, 1,
        0,
        'How many thoughts are added when you hit without killing')

SECTION:addSlider('tracking_added_alpha', 'Tracking Added Alpha',
        0, 1, 0.1,
        0.3,
        'Alpha to add when tracking outburst occurs')
SECTION:addSlider('tracking_added_zoom', 'Tracking Added Size',
        0, 10, 0.1,
        1,
        'How much bigger thoughts are when tracking outburst occurs')
SECTION:addSlider('tracking_added_red', 'Tracking Added Red',
        0, 1, 0.01,
        0.4, -- 100/255
        'How much redder thoughts are when tracking outburst occurs')
SECTION:addSlider('tracking_added_elements', 'Tracking Added Thoughts',
        0, 100, 1,
        12,
        'How many thoughts are added when tracking outburst occurs')


SECTION:addSeparator()

SECTION:addSlider('max_move_towards_zombie', 'Movement Towards Zombies',
        0, 10000, 10,
        50,
        'How many pixels the thoughts move towards closest zombie during their lifetime')

SECTION:addSlider('rear_danger_move', 'Movement in Rear Danger',
        0, 10000, 10,
        150,
        'How many pixels the thoughts move towards closest zombie during their lifetime when the zombie is behind you, unseen')

SECTION:addSlider('movement_multiplier_tracking_start', 'Movement Multiplier when Tracking Starts',
        0, 100, 0.1,
        8,
        'Thoughts movement multiplies by this when you cannot control your character at the start of Tracking outburst.')

SECTION:addSlider('movement_multiplier_tracking', 'Movement Multiplier when Tracking',
        0, 100, 0.1,
        4,
        "Thoughts movement multiplies by this while Tracking outburst lasts.")

SECTION:addSlider('thoughts_overwrite_corruption_time', 'Thoughts Change Corruption Time (ms)',
        0, 60000, 50,
        500,
        'For how long thoughts appear ineligible after they are forcefully overwritten by an event')

SECTION:addSlider('screen_edges_bias', 'Bias Towards Screen Edges',
        0.1, 10, 0.1,
        1.2,
        'Where most of the thoughts spawn;\nExactly 1 for uniform, more than 1 to bias towards edges, less than 1 towards center')

SECTION:addSlider('distance_to_cursor_to_fade', 'Distance to Cursor to Fade',
        10, 1000, 10,
        500,
        'Distance to cursor within which the thought will fade out the closer it is to cursor')

SECTION:addSlider('transparent_at_cursor_distance', 'Become Transparent at Distance to Cursor',
        10, 1000, 10,
        100,
        'Distance to cursor at which the thought becomes fully transparent')



local MO = {
    max_cooldown = 500, -- ms

    min_red = 100 / 255,
    max_red = 120 / 255,

    color_g = 6 / 255,
    color_b = 6 / 255,

    element_peak_at = 0.3, -- max alpha at
    event_add_peak = 0.1,
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
