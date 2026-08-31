local BloodlustTrait = require('bloodlusto/Registries').traits.Bloodlust
local Bloodlust = require('bloodlusto/Bloodlust')
local Utils = require('bloodlusto/Utils')


local SB = require('bloodlusto/Sandbox')
local CSB = require('bloodlusto/ControlSandbox')

local MO = require('bloodlusto/IntrusiveThoughtsOptions')



local IntrusiveThoughts = BloodlustO_IntrusiveThoughts or {}
BloodlustO_IntrusiveThoughts = IntrusiveThoughts


IntrusiveThoughts.screen_width = getCore():getScreenWidth()
IntrusiveThoughts.screen_height = getCore():getScreenHeight()

IntrusiveThoughts.elements = {}

IntrusiveThoughts.last_spawn = 0
IntrusiveThoughts.prev_thoughts_type = nil



--- @class IntrusiveThoughtsEvent
--- @field type string
--- @field thoughts_duration number | nil
--- @field add_duration number | nil
--- @field ends_at number
--- @field thoughts_end_at number | nil
--- @field add_ends_at number | nil
--- @field added_alpha number | nil
--- @field added_zoom number | nil
--- @field added_red number | nil

--- @type IntrusiveThoughtsEvent
IntrusiveThoughts.event = nil

--- @param player IsoPlayer
--- @param type string
function IntrusiveThoughts.onEvent(player, type)
    if player ~= getPlayer() then return end
    if IntrusiveThoughts.event and IntrusiveThoughts.event.type ~= type then
        if type ~= "instakill" and type ~= "tracking" then
            if IntrusiveThoughts.event.type == "instakill" then return end
            if IntrusiveThoughts.event.type == "hurt" and type ~= "kill" then return end
            if (IntrusiveThoughts.event.type == "kill" or IntrusiveThoughts.event.type == "instakill") and type == "hit" then return end
        end
    end
    local thoughts_duration = MO[type..'_thoughts_duration']
    local add_duration = MO[type..'_add_duration']
    if not add_duration and type == "tracking" then
        add_duration = CSB.TrackingMovementLockSeconds * 1000
    end
    if not thoughts_duration and not add_duration then return end
    local at = getTimeInMillis()
    local duration = math.max(thoughts_duration or 0, add_duration or 0)
    IntrusiveThoughts.event = {
        type = type,
        thoughts_duration = thoughts_duration,
        add_duration = add_duration,
        ends_at = at + duration,
        thoughts_end_at = thoughts_duration and at + thoughts_duration or nil,
        add_ends_at = add_duration and at + add_duration or nil,
        added_alpha = MO[type..'_added_alpha'],
        added_zoom = MO[type..'_added_zoom'],
        added_red = MO[type..'_added_red'],
        added_elements = MO[type..'_added_elements'],
    }
end


IntrusiveThoughts.last_zombie_closeness = 0

function IntrusiveThoughts.render()
    local player = getPlayer()
    if not player then return end
    if not player:hasTrait(BloodlustTrait) then return end

    local instance = Bloodlust.getInstance(player)
    if not instance.player then return end
    local data = instance.data

    local intensity = math.max(0, IntrusiveThoughts.getBaseIntensity(player, data))
    if intensity <= 0 and #IntrusiveThoughts.elements == 0 then return end

    local now = getTimeInMillis()

    if IntrusiveThoughts.event and now > IntrusiveThoughts.event.ends_at then
        IntrusiveThoughts.event = nil
    end


    -- Intensity-derived properties
    local target_count = math.floor(MO.max_elements * intensity)
    local cooldown = MO.max_cooldown * (1 - intensity)

    local alpha = MO.max_alpha * intensity
    local zoom = (MO.max_zoom - MO.min_zoom) * intensity
    local redness = MO.min_red + (MO.max_red - MO.min_red) * intensity

    local shake = MO.max_shake * intensity
    local color_flicker = MO.max_color_flicker * intensity
    local zoom_flicker = MO.max_zoom_flicker * intensity

    local text_corruption = MO.max_text_corruption * intensity
    local corrupt_interval = MO.min_text_corruption_interval + (MO.max_text_corruption_interval - MO.min_text_corruption_interval) * (1 - intensity)


    -- Zombie close modifier
    local is_zombie_close = IntrusiveThoughts.isZombieClose(data)
    if is_zombie_close or IntrusiveThoughts.last_zombie_closeness > 0 then
        local target_closeness
        if is_zombie_close then
            target_closeness = 1 - math.clamp((data.distance_to_zombie - MO.min_zombie_tiles)
                / (MO.max_zombie_tiles - MO.min_zombie_tiles),
                0, 1
            )
        else
            target_closeness = 0
        end
        local closeness
        if target_closeness >= IntrusiveThoughts.last_zombie_closeness then
            closeness = target_closeness
        else
            closeness = math.max(target_closeness, IntrusiveThoughts.last_zombie_closeness - 0.025)
        end
        IntrusiveThoughts.last_zombie_closeness = closeness

        target_count = target_count + (MO.zombie_close_added_elements * closeness)

        alpha = alpha + (MO.zombie_close_added_alpha * closeness)
        zoom = zoom + (MO.zombie_close_added_zoom * closeness)

        shake = shake + (MO.zombie_close_added_shake * closeness)

        local max_corruption = MO.zombie_close_min_text_corruption
            + (MO.max_text_corruption - MO.zombie_close_min_text_corruption) * (1 - closeness)
        text_corruption = max_corruption * intensity
    end


    -- Event modifier
    local ev_mod = {}
    local ev = IntrusiveThoughts.event
    if ev and ev.add_ends_at and now < ev.add_ends_at then
        local remaining = ev.add_ends_at - now

        local elapsed = ev.add_duration - remaining
        local peak_at = ev.add_duration * MO.event_add_peak

        local progress
        if elapsed < peak_at then
            progress = elapsed / peak_at
        else
            progress = remaining / (ev.add_duration - peak_at)
        end

        if ev.added_alpha then
            ev_mod.alpha = ev.added_alpha * progress
        end
        if ev.added_zoom then
            ev_mod.zoom = ev.added_zoom * progress
        end
        if ev.added_red then
            ev_mod.redness = ev.added_red * progress
        end
        if ev.added_elements then
            target_count = target_count + (ev.added_elements * progress)
            cooldown = 0
        end
    end


    -- Thoughts
    local thoughts_mod = IntrusiveThoughts.getThoughtsMod(data)
    local thoughts_type = IntrusiveThoughts.getThoughtsType(instance, data)
    if thoughts_type ~= IntrusiveThoughts.prev_thoughts_type and (
        thoughts_type == 'hurt'
        or thoughts_type == "kill"
        or thoughts_type == "instakill"
        or thoughts_type == "rear-danger" or IntrusiveThoughts.prev_thoughts_type == "rear-danger")
    then
        IntrusiveThoughts.overwriteThoughts(thoughts_mod, thoughts_type)
        IntrusiveThoughts.overwrote_thoughts_at = now
    end
    IntrusiveThoughts.prev_thoughts_type = thoughts_type

    -- Thoughts overwrite text corruption
    if IntrusiveThoughts.overwrote_thoughts_at then
        if now - IntrusiveThoughts.overwrote_thoughts_at < MO.thoughts_overwrite_corruption_time then
            corrupt_interval = 0
            text_corruption = 1
            for _, el in ipairs(IntrusiveThoughts.elements) do
                el.next_recorrupt_at = 0
            end
        else
            IntrusiveThoughts.overwrote_thoughts_at = nil
        end
    end

    -- Lifecycle
    IntrusiveThoughts.removeExpired()
    IntrusiveThoughts.recorrupt(corrupt_interval, text_corruption)
    IntrusiveThoughts.moveTowardsZombie(instance)
    if intensity > 0 then
        IntrusiveThoughts.spawn(target_count, cooldown, thoughts_mod, thoughts_type, corrupt_interval)
    end


    -- Draw all elements
    IntrusiveThoughts.drawElements(alpha, redness, zoom, shake, zoom_flicker, color_flicker, ev_mod)
end


function IntrusiveThoughts.getBaseIntensity(player, data)
    local min_bloodlust
    local max_bloodlust
    if data.frenzy_progress >= SB.BloodlustOverreducedForFrenzy then
        min_bloodlust = MO.min_frenzy_bloodlust
        max_bloodlust = MO.max_at_frenzy_bloodlust
    else
        min_bloodlust = MO.min_bloodlust
        max_bloodlust = MO.max_at_bloodlust
    end
    if data.bloodlust < min_bloodlust then return 0 end
    if data.bloodlust > max_bloodlust then return 1 end
    return (data.bloodlust - min_bloodlust) / (max_bloodlust - min_bloodlust)
end


function IntrusiveThoughts.isZombieClose(data)
    return data.distance_to_zombie and data.distance_to_zombie <= MO.max_zombie_tiles
end


function IntrusiveThoughts.getThoughtsMod(data)
    return data.frenzy_progress >= SB.BloodlustOverreducedForFrenzy and ":frenzy:" or ":"
end

--- @param instance Bloodlust
--- @param data BloodlustModData
function IntrusiveThoughts.getThoughtsType(instance, data)
    if instance.is_rear_danger then
        return 'rear-danger'
    elseif IntrusiveThoughts.event and IntrusiveThoughts.event.thoughts_end_at
            and getTimeInMillis() < IntrusiveThoughts.event.thoughts_end_at then
        return IntrusiveThoughts.event.type
    elseif IntrusiveThoughts.isZombieClose(data) then
        if instance.can_see_closest_zombie then
            return 'facing-zombie'
        else
            return 'zombie-nearby'
        end
    else
        return 'high-bloodlust'
    end
end

function IntrusiveThoughts.overwriteThoughts(thoughts_mod, thoughts_type)
    for _, e in ipairs(IntrusiveThoughts.elements) do
        local text = Utils.getVariant('intrusive-thought'..thoughts_mod..thoughts_type, 'Kill')
        e.original_text = text
        e.corrupted_text = text
    end
end


function IntrusiveThoughts.removeExpired()
    local now = getTimeInMillis()
    local i = 1
    while i <= #IntrusiveThoughts.elements do
        if now > IntrusiveThoughts.elements[i].expires_at then
            table.remove(IntrusiveThoughts.elements, i)
        else
            i = i + 1
        end
    end
end


function IntrusiveThoughts.recorrupt(interval, intensity)
    local now = getTimeInMillis()
    for _, el in ipairs(IntrusiveThoughts.elements) do
        if now > el.next_recorrupt_at then
            el.corrupted_text = IntrusiveThoughts.corruptText(el.original_text, intensity)
            el.next_recorrupt_at = now + interval
        end
    end
end


function IntrusiveThoughts.isoToScreen(obj)
    local x = obj:getX()
    local y = obj:getY()
    local z = obj:getZ()
    local zoom = getCore():getZoom(0)
    local camera_off_x = IsoCamera.getOffX()
    local camera_off_y = IsoCamera.getOffY()
    return {
        x = (IsoUtils.XToScreen(x, y, z, 0) - camera_off_x) / zoom,
        y = (IsoUtils.YToScreen(x, y, z, 0) - camera_off_y) / zoom
    }
end

IntrusiveThoughts.last_moved_at = nil

--- @param instance Bloodlust
function IntrusiveThoughts.moveTowardsZombie(instance)
    if not instance.closest_zombie then return end
    local target = IntrusiveThoughts.isoToScreen(instance.closest_zombie)

    local movement = MO.max_move_towards_zombie
    if instance.is_rear_danger then
        movement = MO.rear_danger_move
    end
    if instance.control.outburst == "tracking" then
        if instance.control.tracking_movement_lock_ends_at then
            movement = movement * MO.movement_multiplier_tracking_start
        else
            movement = movement * MO.movement_multiplier_tracking
        end
    end

    local now = getTimeInMillis()
    local delta = IntrusiveThoughts.last_moved_at and now - IntrusiveThoughts.last_moved_at or 0

    for _, el in ipairs(IntrusiveThoughts.elements) do
        local step = movement * (delta / el.duration)

        local dx = target.x - el.x
        local dy = target.y - el.y
        local dist = math.sqrt(dx * dx + dy * dy)

        if dist > 0 then
            el.x = el.x + (dx / dist) * step
            el.y = el.y + (dy / dist) * step
        end
    end
    IntrusiveThoughts.last_moved_at = now
end


function IntrusiveThoughts.getRandomPositionFactor()
    local u = ZombRandFloat(0, 1)
    if u < 0.5 then
        return 0.5 * (2 * u) ^ MO.screen_edges_bias
    else
        return 1 - 0.5 * (2 * (1 - u)) ^ MO.screen_edges_bias
    end
end

function IntrusiveThoughts.spawn(target_count, cooldown, thoughts_mod, thoughts_type, corrupt_interval)
    if #IntrusiveThoughts.elements >= target_count then return end
    local now = getTimeInMillis()
    if IntrusiveThoughts.last_spawn + cooldown > now then return end
    IntrusiveThoughts.last_spawn = now

    local duration = ZombRandFloat(
        MO.min_element_time,
        MO.max_element_time
    )
    local text = Utils.getVariant('intrusive-thought'..thoughts_mod..thoughts_type, 'Kill')
    table.insert(IntrusiveThoughts.elements, {
        original_text = text,
        corrupted_text = text,
        next_recorrupt_at = now + corrupt_interval,

        x = IntrusiveThoughts.screen_width * IntrusiveThoughts.getRandomPositionFactor(),
        y = IntrusiveThoughts.screen_height * IntrusiveThoughts.getRandomPositionFactor(),

        zoom_rand = ZombRandFloat(0, 1),
        ev_responsiveness = ZombRandFloat(MO.min_event_responsiveness, 1.0),

        duration = duration,
        expires_at = now + duration,

        frames = 0
    })
end



function IntrusiveThoughts.drawElements(max_alpha, max_redness, max_zoom, shake, zoom_flicker, color_flicker, ev_mod)
    local mx = getMouseX()
    local my = getMouseY()

    local now = getTimeInMillis()
    local txt = getTextManager()
    for _, el in ipairs(IntrusiveThoughts.elements) do
        local remaining = el.expires_at - now

        local elapsed = el.duration - remaining
        local peak_at = el.duration * MO.element_peak_at

        local progress
        if elapsed < peak_at then
            progress = elapsed / peak_at
        else
            progress = remaining / (el.duration - peak_at)
        end

        -- Apply event
        local alpha = max_alpha
        if ev_mod.alpha then
            alpha = alpha + (ev_mod.alpha * el.ev_responsiveness)
        end
        local zoom = max_zoom
        if ev_mod.zoom then
            zoom = zoom + (ev_mod.zoom * el.ev_responsiveness)
        end
        local redness = max_redness
        if ev_mod.redness then
            redness = redness + (ev_mod.redness * el.ev_responsiveness)
        end

        -- Reduce alpha closer to cursor
        local mdist = math.abs(el.x - mx) + math.abs(el.y - my)
        if mdist < MO.transparent_at_cursor_distance then
            alpha = 0
            el.expires_at = 0
        elseif mdist < MO.distance_to_cursor_to_fade then
            alpha = alpha * ((mdist - MO.transparent_at_cursor_distance) / (MO.distance_to_cursor_to_fade - MO.transparent_at_cursor_distance))
        end

        txt:DrawString(
            UIFont.Large,
            el.x + ZombRandFloat(-shake, shake),
            el.y + ZombRandFloat(-shake, shake),
            (MO.min_zoom + zoom * el.zoom_rand) + ZombRandFloat(0, zoom_flicker),
            el.corrupted_text,
            redness + ZombRandFloat(-color_flicker, color_flicker),
            MO.color_g + ZombRandFloat(-color_flicker, color_flicker),
            MO.color_b + ZombRandFloat(-color_flicker, color_flicker),
            alpha * progress
        )
    end
end



--region Text Corruption

-- https://pc.net/resources/leet_sheet
IntrusiveThoughts.TEXT_CORRUPTION_REPLACEMENTS = {
    a = {"@", "4", "^"},
    b = {"8", "6", "13", "|3", "ß"},
    c = {"©", "¢", "("},
    d = {")", "?"},
    e = {"3", "€", "ë"},
    f = {"ƒ"},
    g = {"6", "9", "&"},
    h = {"#", "}{"},
    i = {"1", "!", "¡", "|", "]"},
    j = {"]", "¿"},
    k = {"X", "|<"},
    l = {"|", "1", "£", "1_", "¬"},
    m = {"^^"},
    n = {"/V"},
    o = {"0", "()", "°"},
    p = {"¶", "|°", "9"},
    q = {"9"},
    r = {"2", "®"},
    s = {"5", "$", "§"},
    t = {"7", "+", "†"},
    u = {"µ"},
    v = {"^"},
    x = {"%", "*", "><"},
    y = {"¥", "J", "'/", "j"},
    z = {"2", "%"}
}

IntrusiveThoughts.TEXT_CORRUPTION_SUFFIXES = {
    ".",
    "...",
    ". . .",
    "!...",
    "!",
    "!!",
    "?!",
    " :) ",
}

function IntrusiveThoughts.corruptText(text, intensity)
    local chars = {}
    for i = 1, #text do
        chars[i] = text:sub(i, i)
    end

    local result = {}
    for i, char in ipairs(chars) do
        local roll = ZombRandFloat(0, 1)

        if roll < 0.1*intensity then
            -- Similar-looking replacements
            local replacements = IntrusiveThoughts.TEXT_CORRUPTION_REPLACEMENTS[string.lower(char)]
            if replacements then
                char = replacements[ZombRand(#replacements) + 1]
            end
        elseif roll < 0.5*intensity then
            -- Random capitalization
            if ZombRand(2) == 0 then
                char = string.upper(char)
            else
                char = string.lower(char)
            end
        end

        -- Possibility to skip character
        if ZombRandFloat(0, 1) > 0.05*intensity then
            table.insert(result, char)
        end
    end

    local output = table.concat(result)

    -- Random suffixes
    if ZombRandFloat(0, 1) < 0.3*intensity then
        output = output .. IntrusiveThoughts.TEXT_CORRUPTION_SUFFIXES[ZombRand(#IntrusiveThoughts.TEXT_CORRUPTION_SUFFIXES) + 1]
    end

    return output
end

--endregion



--region Events

Bloodlust.registerEventListener(IntrusiveThoughts.onEvent)

Events.OnPreUIDraw.Add(IntrusiveThoughts.render)

function IntrusiveThoughts.onGameBoot()
    IntrusiveThoughts.screen_width = getCore():getScreenWidth()
    IntrusiveThoughts.screen_height = getCore():getScreenHeight()
end
Events.OnGameBoot.Add(IntrusiveThoughts.onGameBoot)

function IntrusiveThoughts.onScreenSizeChange( _old_width, _old_height, new_width, new_height )
    IntrusiveThoughts.screen_width = new_width
    IntrusiveThoughts.screen_height = new_height
end
Events.OnResolutionChange.Add(IntrusiveThoughts.onScreenSizeChange)

--endregion


return IntrusiveThoughts
