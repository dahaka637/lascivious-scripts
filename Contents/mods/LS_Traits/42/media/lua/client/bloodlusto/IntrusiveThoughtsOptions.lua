local function text(key)
    return getText('UI_BloodlustO_IntrusiveThoughtsOptions_'..key)
end

local SECTION = PZAPI.ModOptions:create('BloodlustO_IntrusiveThoughts', text('Title'))


SECTION:addDescription(text('Description'))

SECTION:addTickBox('enable', text('enable'), true)


SECTION:addSlider('min_bloodlust', text('min_bloodlust'),
        0, 100, 1,
        60,
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


SECTION:addSeparator()


SECTION:addSlider('max_elements', text('max_elements'),
        1, 1000, 1,
        16,
        text('max_elements_tooltip'))
SECTION:addSlider('min_element_time', text('min_element_time'),
        50, 60000, 50,
        500,
        text('min_element_time_tooltip'))
SECTION:addSlider('max_element_time', text('max_element_time'),
        50, 60000, 50,
        3000,
        text('max_element_time_tooltip'))

SECTION:addSlider('max_alpha', text('max_alpha'),
        0, 1, 0.1,
        0.9,
        text('max_alpha_tooltip'))
SECTION:addSlider('min_zoom', text('min_zoom'),
        0.1, 10, 0.1,
        0.8,
        text('min_zoom_tooltip'))
SECTION:addSlider('max_zoom', text('max_zoom'),
        0.1, 10, 0.1,
        2,
        text('max_zoom_tooltip'))

SECTION:addSlider('max_shake', text('max_shake'),
        0, 10, 1,
        1,
        text('max_shake_tooltip'))
SECTION:addSlider('max_zoom_flicker', text('max_zoom_flicker'),
        0, 10, 0.1,
        0.1,
        text('max_zoom_flicker_tooltip'))
SECTION:addSlider('max_color_flicker', text('max_color_flicker'),
        0, 1, 0.01,
        0.07, -- 20/255
        text('max_color_flicker_tooltip'))

SECTION:addSlider('max_text_corruption', text('max_text_corruption'),
        0, 1, 0.1,
        0.9,
        text('max_text_corruption_tooltip'))
SECTION:addSlider('max_text_corruption_interval', text('max_text_corruption_interval'),
        0, 60000, 50,
        250,
        text('max_text_corruption_interval_tooltip'))
SECTION:addSlider('min_text_corruption_interval', text('min_text_corruption_interval'),
        0, 60000, 50,
        50,
        text('min_text_corruption_interval_tooltip'))


SECTION:addSeparator()


SECTION:addSlider('max_zombie_tiles', text('max_zombie_tiles'),
        0, 1000, 1,
        6,
        text('max_zombie_tiles_tooltip'))
SECTION:addSlider('min_zombie_tiles', text('min_zombie_tiles'),
        0, 1000, 1,
        2,
        text('min_zombie_tiles_tooltip'))

SECTION:addSlider('zombie_close_added_elements', text('zombie_close_added_elements'),
        0, 1000, 1,
        4,
        text('zombie_close_added_elements_tooltip'))
SECTION:addSlider('zombie_close_added_alpha', text('zombie_close_added_alpha'),
        0, 1, 0.05,
        0.25,
        text('zombie_close_added_alpha_tooltip'))
SECTION:addSlider('zombie_close_added_zoom', text('zombie_close_added_zoom'),
        0, 100, 1,
        1,
        text('zombie_close_added_zoom_tooltip'))
SECTION:addSlider('zombie_close_added_shake', text('zombie_close_added_shake'),
        0, 100, 1,
        2,
        text('zombie_close_added_shake_tooltip'))
SECTION:addSlider('zombie_close_min_text_corruption', text('zombie_close_min_text_corruption'),
        0, 1, 0.05,
        0.25,
        text('zombie_close_min_text_corruption_tooltip'))


SECTION:addSeparator()


SECTION:addSlider('min_event_responsiveness', text('min_event_responsiveness'),
        0, 1, 0.1,
        0.6,
        text('min_event_responsiveness_tooltip'))

SECTION:addSlider('hurt_thoughts_duration', text('hurt_thoughts_duration'),
        50, 60000, 50,
        10000,
        text('hurt_thoughts_duration_tooltip'))
SECTION:addSlider('hurt_add_duration', text('hurt_add_duration'),
        50, 60000, 50,
        4000,
        text('hurt_add_duration_tooltip'))
SECTION:addSlider('hurt_added_alpha', text('hurt_added_alpha'),
        0, 1, 0.1,
        0.5,
        text('hurt_added_alpha_tooltip'))
SECTION:addSlider('hurt_added_zoom', text('hurt_added_zoom'),
        0, 10, 0.1,
        3,
        text('hurt_added_zoom_tooltip'))
SECTION:addSlider('hurt_added_red', text('hurt_added_red'),
        0, 1, 0.01,
        0.4, -- 100/255
        text('hurt_added_red_tooltip'))
SECTION:addSlider('hurt_added_elements', text('hurt_added_elements'),
        0, 100, 1,
        5,
        text('hurt_added_elements_tooltip'))

SECTION:addSlider('kill_thoughts_duration', text('kill_thoughts_duration'),
        50, 60000, 50,
        10000,
        text('kill_thoughts_duration_tooltip'))
SECTION:addSlider('kill_add_duration', text('kill_add_duration'),
        50, 60000, 50,
        3000,
        text('kill_add_duration_tooltip'))
SECTION:addSlider('kill_added_alpha', text('kill_added_alpha'),
        0, 1, 0.1,
        0.5,
        text('kill_added_alpha_tooltip'))
SECTION:addSlider('kill_added_zoom', text('kill_added_zoom'),
        0, 10, 0.1,
        1,
        text('kill_added_zoom_tooltip'))
SECTION:addSlider('kill_added_red', text('kill_added_red'),
        0, 1, 0.01,
        0.31, -- 80/255
        text('kill_added_red_tooltip'))
SECTION:addSlider('kill_added_elements', text('kill_added_elements'),
        0, 100, 1,
        10,
        text('kill_added_elements_tooltip'))

SECTION:addSlider('instakill_thoughts_duration', text('instakill_thoughts_duration'),
        50, 60000, 50,
        10000,
        text('instakill_thoughts_duration_tooltip'))
SECTION:addSlider('instakill_add_duration', text('instakill_add_duration'),
        50, 60000, 50,
        3000,
        text('instakill_add_duration_tooltip'))
SECTION:addSlider('instakill_added_alpha', text('instakill_added_alpha'),
        0, 1, 0.1,
        0.5,
        text('instakill_added_alpha_tooltip'))
SECTION:addSlider('instakill_added_zoom', text('instakill_added_zoom'),
        0, 10, 0.1,
        2,
        text('instakill_added_zoom_tooltip'))
SECTION:addSlider('instakill_added_red', text('instakill_added_red'),
        0, 1, 0.01,
        0.58, -- 150/255
        text('instakill_added_red_tooltip'))
SECTION:addSlider('instakill_added_elements', text('instakill_added_elements'),
        0, 100, 1,
        20,
        text('instakill_added_elements_tooltip'))

SECTION:addSlider('hit_thoughts_duration', text('hit_thoughts_duration'),
        50, 60000, 50,
        3000,
        text('hit_thoughts_duration_tooltip'))
SECTION:addSlider('hit_add_duration', text('hit_add_duration'),
        50, 60000, 50,
        500,
        text('hit_add_duration_tooltip'))
SECTION:addSlider('hit_added_alpha', text('hit_added_alpha'),
        0, 1, 0.1,
        0.2,
        text('hit_added_alpha_tooltip'))
SECTION:addSlider('hit_added_zoom', text('hit_added_zoom'),
        0, 10, 0.1,
        0.5,
        text('hit_added_zoom_tooltip'))
SECTION:addSlider('hit_added_red', text('hit_added_red'),
        0, 1, 0.01,
        0.19, -- 50/255
        text('hit_added_red_tooltip'))
SECTION:addSlider('hit_added_elements', text('hit_added_elements'),
        0, 100, 1,
        0,
        text('hit_added_elements_tooltip'))

SECTION:addSlider('tracking_added_alpha', text('tracking_added_alpha'),
        0, 1, 0.1,
        0.3,
        text('tracking_added_alpha_tooltip'))
SECTION:addSlider('tracking_added_zoom', text('tracking_added_zoom'),
        0, 10, 0.1,
        1,
        text('tracking_added_zoom_tooltip'))
SECTION:addSlider('tracking_added_red', text('tracking_added_red'),
        0, 1, 0.01,
        0.4, -- 100/255
        text('tracking_added_red_tooltip'))
SECTION:addSlider('tracking_added_elements', text('tracking_added_elements'),
        0, 100, 1,
        12,
        text('tracking_added_elements_tooltip'))


SECTION:addSeparator()

SECTION:addSlider('max_move_towards_zombie', text('max_move_towards_zombie'),
        0, 10000, 10,
        50,
        text('max_move_towards_zombie_tooltip'))

SECTION:addSlider('rear_danger_move', text('rear_danger_move'),
        0, 10000, 10,
        150,
        text('rear_danger_move_tooltip'))

SECTION:addSlider('movement_multiplier_tracking_start', text('movement_multiplier_tracking_start'),
        0, 100, 0.1,
        8,
        text('movement_multiplier_tracking_start_tooltip'))

SECTION:addSlider('movement_multiplier_tracking', text('movement_multiplier_tracking'),
        0, 100, 0.1,
        4,
        text('movement_multiplier_tracking_tooltip'))

SECTION:addSlider('thoughts_overwrite_corruption_time', text('thoughts_overwrite_corruption_time'),
        0, 60000, 50,
        500,
        text('thoughts_overwrite_corruption_time_tooltip'))

SECTION:addSlider('screen_edges_bias', text('screen_edges_bias'),
        0.1, 10, 0.1,
        1.2,
        text('screen_edges_bias_tooltip'))

SECTION:addSlider('distance_to_cursor_to_fade', text('distance_to_cursor_to_fade'),
        10, 1000, 10,
        500,
        text('distance_to_cursor_to_fade_tooltip'))

SECTION:addSlider('transparent_at_cursor_distance', text('transparent_at_cursor_distance'),
        10, 1000, 10,
        100,
        text('transparent_at_cursor_distance_tooltip'))



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
