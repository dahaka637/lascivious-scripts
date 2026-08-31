local BloodlustTrait = require("bloodlusto/Registries").traits.Bloodlust
local Bloodlust = require('bloodlusto/Bloodlust')


local SB = require('bloodlusto/Sandbox')
local CSB = require('bloodlusto/ControlSandbox')

local MO = require('bloodlusto/RedVisionOptions')


local RedVision = BloodlustO_RedVision or {}
BloodlustO_RedVision = RedVision

RedVision.texture = getTexture("media/textures/gui/bloodlust-overwhelming-overlay.png")
RedVision.screen_width = getCore():getScreenWidth()
RedVision.screen_height = getCore():getScreenHeight()

RedVision.current_alpha = 0
--- @type { type: string, added_alpha: number, duration: number, ends_at: number } | nil
RedVision.current_event = nil



--- @param player IsoPlayer
--- @param type string
function RedVision.onEvent(player, type)
    if player ~= getPlayer() then return end
    local added_alpha = MO[type..'_event_added_alpha']
    local duration = MO[type..'_event_duration']
    if not duration and type == "tracking" then
        duration = CSB.TrackingMovementLockSeconds * 1000
    end
    if not duration then return end
    local ends_at = getTimeInMillis() + duration
    if RedVision.current_event and RedVision.current_event.added_alpha > added_alpha then return end
    RedVision.current_event = {
        type = type,
        added_alpha = added_alpha,
        duration = duration,
        ends_at = ends_at
    }
end



--- @param player IsoPlayer
--- @param data BloodlustModData
function RedVision.calculateBaseAlpha(player, data)
    local min_bloodlust
    local max_bloodlust
    if data.frenzy_progress >= SB.BloodlustOverreducedForFrenzy then
        min_bloodlust = MO.min_frenzy_bloodlust
        max_bloodlust = MO.max_at_frenzy_bloodlust
    else
        min_bloodlust = MO.min_bloodlust
        max_bloodlust = MO.max_at_bloodlust
    end

    local bloodlust_factor = (data.bloodlust - min_bloodlust) / (max_bloodlust - min_bloodlust)
    return MO.max_alpha * math.min(1, bloodlust_factor)
end

--- @param base_alpha number
function RedVision.applyEvent(base_alpha)
    local ev = RedVision.current_event
    if not ev then
        return base_alpha
    end

    local remaining = ev.ends_at - getTimeInMillis()
    if remaining <= 0 then
        RedVision.current_event = nil
        return base_alpha
    end

    local elapsed = ev.duration - remaining
    local peak_at
    if ev.type == "tracking" then
        peak_at = ev.duration * MO.tracking_event_peak
    else
        peak_at = ev.duration * MO.event_peak
    end

    local progress
    if elapsed < peak_at then
        progress = elapsed / peak_at
    else
        progress = remaining / (ev.duration - peak_at)
    end
    return base_alpha + ev.added_alpha * progress
end

--- @param target_alpha number
function RedVision.transitionAlpha(target_alpha)
    local alpha_difference = target_alpha - RedVision.current_alpha
    if alpha_difference > 0 then
        RedVision.current_alpha = RedVision.current_alpha + math.min(MO.in_rate, alpha_difference)
    elseif alpha_difference < 0 then
        RedVision.current_alpha = RedVision.current_alpha - math.min(MO.out_rate, -alpha_difference)
    end
    return RedVision.current_alpha
end


RedVision.current_blink = 0
RedVision.blink_duration = 0
RedVision.next_blink_at = getTimeInMillis()
--- @param alpha number
--- @param instance Bloodlust
function RedVision.applyBlinking(alpha, instance)
    local now = getTimeInMillis()

    local max_change, min_duration, max_duration

    if instance.control.outburst == "tracking" then
        -- TODO Mod Options for these, and maybe tweak them further
        if instance.control.tracking_movement_lock_ends_at then
            max_change = 0.05
            min_duration = 50
            max_duration = 150
        else
            max_change = 0.01
            min_duration = 80
            max_duration = 120
        end
    end

    if not max_change then
        RedVision.current_blink = 0
        RedVision.next_blink_at = now
        return alpha
    end

    if now > RedVision.next_blink_at then
        RedVision.current_blink = ZombRandFloat(0, max_change)
        RedVision.blink_duration = ZombRand(min_duration, max_duration)
        RedVision.next_blink_at = now + RedVision.blink_duration
    end

    local progress = (RedVision.next_blink_at - now) / RedVision.blink_duration
    if progress > 0.5 then progress = 1 - progress end
    return alpha + (RedVision.current_blink * progress)
end

--- @param alpha number
function RedVision.overlayTexture(alpha)
    if alpha > 0 then
        UIManager.DrawTexture(RedVision.texture, 0, 0, RedVision.screen_width, RedVision.screen_height, alpha)
    end
end



function RedVision.render()
    if not MO.enable then return end

    local player = getPlayer()
    if not player then return end
    if not player:hasTrait(BloodlustTrait) then return end
    local instance = Bloodlust.getInstance(player)
    if not instance.player then return end

    local base_alpha = RedVision.calculateBaseAlpha(player, instance.data)
    local current_base_alpha = RedVision.transitionAlpha(base_alpha)

    local alpha = RedVision.applyEvent(current_base_alpha)

    alpha = RedVision.applyBlinking(alpha, instance)

    RedVision.overlayTexture(alpha)
end



--region Events

Bloodlust.registerEventListener(RedVision.onEvent)

function RedVision.onGameBoot()
    RedVision.screen_width = getCore():getScreenWidth()
    RedVision.screen_height = getCore():getScreenHeight()
end
Events.OnGameBoot.Add(RedVision.onGameBoot)

function RedVision.onScreenSizeChange( _old_width, _old_height, new_width, new_height )
    RedVision.screen_width = new_width
    RedVision.screen_height = new_height
end
Events.OnResolutionChange.Add(RedVision.onScreenSizeChange)

Events.OnPreUIDraw.Add(RedVision.render)

return RedVision

--endregion
