require "ISUI/ISPanel"
require "ISUI/ISInventoryItem"
require "LasciviousShop_Shared"

local LS = LasciviousShop

LasciviousShopUI = LasciviousShopUI or {}
local UI = LasciviousShopUI

UI.col = {
    bg        = { r=0.035, g=0.027, b=0.051 },
    panel     = { r=0.063, g=0.043, b=0.098 },
    panel2    = { r=0.090, g=0.063, b=0.125 },
    card      = { r=0.090, g=0.063, b=0.125 },
    cardHi    = { r=0.129, g=0.086, b=0.184 },
    line      = { r=0.212, g=0.145, b=0.267 },
    lineHi    = { r=0.337, g=0.188, b=0.486 },
    accent    = { r=0.659, g=0.333, b=0.969 },
    accentHi  = { r=0.753, g=0.518, b=0.988 },
    accentDim = { r=0.227, g=0.122, b=0.337 },
    text      = { r=0.933, g=0.910, b=0.965 },
    muted     = { r=0.655, g=0.600, b=0.718 },
    gold      = { r=0.969, g=0.788, b=0.282 },
    danger    = { r=1.000, g=0.361, b=0.459 },
    ok        = { r=0.376, g=0.839, b=0.655 },
    -- Light blue, reserved for the faction Comércio upgrade's discount hint
    -- (card price row + cart total note) -- distinct from gold (the price
    -- itself), accent/purple (the shop's own branding), and ok/danger
    -- (success/error), so it reads as its own, unambiguous category at a
    -- glance against the dark purple background.
    discount  = { r=0.455, g=0.741, b=0.988 },
    white     = { r=1, g=1, b=1 },
    black     = { r=0, g=0, b=0 },
    -- Emergency full-cure card only: a light-blue/purple blend (halfway
    -- between `discount` and `accent`) so that one card reads as "special"
    -- at a glance, distinct from every offer/maxed/normal card style.
    cureBorder   = { r=0.557, g=0.537, b=0.979 },
    cureBorderHi = { r=0.667, g=0.654, b=0.985 },
    cureFill     = { r=0.207, g=0.182, b=0.339 },
}

UI.SOUND = {
    open            = "LasciviousShop_Open",
    close           = "LasciviousShop_Close",
    click           = "LasciviousShop_Click",
    cartAdd         = "LasciviousShop_CartAdd",
    cartRemove      = "LasciviousShop_CartRemove",
    purchaseSuccess = "LasciviousShop_PurchaseSuccess",
    error           = "LasciviousShop_Error",
}

-- Frame-rate-normalized delta (~1.0 at 30fps), clamped against stutter --
-- used by UI.glide for the danger-dim fade in LasciviousShop_Window.lua.
function UI.delta()
    local d = UIManager.getMillisSinceLastRender() / 33.3
    if d > 3 then d = 3 end
    return d
end

function UI.glide(current, target, rate)
    local t = rate * UI.delta()
    if t > 1 then t = 1 end
    local value = current + (target - current) * t
    if math.abs(target - value) < 0.002 then return target end
    return value
end

function UI.playSound(soundName)
    if not soundName then return end
    local ok, err = pcall(function() getSoundManager():playUISound(soundName) end)
    if not ok then LS.log("sound playback failed for " .. tostring(soundName) .. ": " .. tostring(err)) end
end

local textures = {}
function UI.tex(name)
    local value = textures[name]
    if value == nil then
        value = getTexture("media/ui/LasciviousShop/" .. tostring(name) .. ".png") or false
        textures[name] = value
    end
    return value == false and nil or value
end

function UI.roundRect(element, x, y, w, h, radius, alpha, color)
    if w <= 0 or h <= 0 then return end
    local tl, tr, bl, br = UI.tex("cnr_tl"), UI.tex("cnr_tr"), UI.tex("cnr_bl"), UI.tex("cnr_br")
    if not (tl and tr and bl and br) then
        element:drawRect(x, y, w, h, alpha, color.r, color.g, color.b)
        return
    end
    radius = math.max(1, math.min(radius, math.floor(math.min(w, h) / 2)))
    element:drawTextureScaled(tl, x, y, radius, radius, alpha, color.r, color.g, color.b)
    element:drawTextureScaled(tr, x + w - radius, y, radius, radius, alpha, color.r, color.g, color.b)
    element:drawTextureScaled(bl, x, y + h - radius, radius, radius, alpha, color.r, color.g, color.b)
    element:drawTextureScaled(br, x + w - radius, y + h - radius, radius, radius, alpha, color.r, color.g, color.b)
    if w > radius * 2 then
        element:drawRect(x + radius, y, w - radius * 2, radius, alpha, color.r, color.g, color.b)
        element:drawRect(x + radius, y + h - radius, w - radius * 2, radius, alpha, color.r, color.g, color.b)
    end
    if h > radius * 2 then
        element:drawRect(x, y + radius, w, h - radius * 2, alpha, color.r, color.g, color.b)
    end
end

function UI.roundFrame(element, x, y, w, h, radius, border, fill, alpha)
    UI.roundRect(element, x, y, w, h, radius, alpha or 1, border)
    UI.roundRect(element, x + 1, y + 1, w - 2, h - 2, math.max(1, radius - 1), alpha or 1, fill)
end

function UI.shadow(element, x, y, w, h, spread, alpha, color)
    local texture = UI.tex("glow")
    if not texture then return end
    color = color or UI.col.black
    element:drawTextureScaled(texture, x - spread, y - spread + 5, w + spread * 2, h + spread * 2,
        alpha or 0.4, color.r, color.g, color.b)
end

function UI.glow(element, x, y, w, h, spread, alpha, color)
    local texture = UI.tex("glow")
    if not texture then return end
    color = color or UI.col.accent
    element:drawTextureScaled(texture, x - spread, y - spread, w + spread * 2, h + spread * 2,
        alpha or 0.12, color.r, color.g, color.b)
end

local fontHeightCache = {}
local textWidthCache, textWidthCacheSize = {}, 0
local fitTextCache, fitTextCacheSize = {}, 0
local TEXT_WIDTH_CACHE_LIMIT = 4096
local FIT_TEXT_CACHE_LIMIT = 4096

function UI.fontHeight(font)
    local cached = fontHeightCache[font]
    if cached then return cached end
    cached = getTextManager():getFontHeight(font)
    fontHeightCache[font] = cached
    return cached
end

function UI.textWidth(font, value)
    value = tostring(value or "")
    local key = tostring(font) .. "\31" .. value
    local cached = textWidthCache[key]
    if cached ~= nil then return cached end
    cached = getTextManager():MeasureStringX(font, value)
    if textWidthCacheSize >= TEXT_WIDTH_CACHE_LIMIT then
        -- A wholesale reset is rare and cheaper than an O(n) LRU shuffle in a
        -- render hot path. Stable labels repopulate on the following frame.
        textWidthCache, textWidthCacheSize = {}, 0
    end
    textWidthCache[key] = cached
    textWidthCacheSize = textWidthCacheSize + 1
    return cached
end

function UI.fitText(value, font, maxWidth)
    value = tostring(value or "")
    if UI.textWidth(font, value) <= maxWidth then return value end
    local suffix = ".."
    if UI.textWidth(font, suffix) > maxWidth then return "" end
    local cacheKey = tostring(font) .. "\31" .. tostring(maxWidth) .. "\31" .. value
    local cached = fitTextCache[cacheKey]
    if cached ~= nil then return cached end

    -- Binary-search UTF-8 character boundaries. The old byte-by-byte loop was
    -- O(n^2) in string measurements and could cut Portuguese names in the
    -- middle of a multibyte character, producing invalid text for the renderer.
    local boundaries = { 0 }
    for index = 2, #value do
        local byte = string.byte(value, index)
        if byte < 128 or byte >= 192 then boundaries[#boundaries + 1] = index - 1 end
    end
    boundaries[#boundaries + 1] = #value
    local low, high, best = 1, #boundaries, 0
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local byteCount = boundaries[middle]
        local candidate = string.sub(value, 1, byteCount) .. suffix
        if UI.textWidth(font, candidate) <= maxWidth then
            best = byteCount
            low = middle + 1
        else
            high = middle - 1
        end
    end
    local result = string.sub(value, 1, best) .. suffix
    if fitTextCacheSize >= FIT_TEXT_CACHE_LIMIT then
        fitTextCache, fitTextCacheSize = {}, 0
    end
    fitTextCache[cacheKey] = result
    fitTextCacheSize = fitTextCacheSize + 1
    return result
end

function UI.text(element, value, x, y, font, color, alpha)
    element:drawText(tostring(value or ""), x, y, color.r, color.g, color.b, alpha or 1, font)
end

function UI.textCentre(element, value, x, y, font, color, alpha)
    element:drawTextCentre(tostring(value or ""), x, y, color.r, color.g, color.b, alpha or 1, font)
end

function UI.textRight(element, value, x, y, font, color, alpha)
    element:drawTextRight(tostring(value or ""), x, y, color.r, color.g, color.b, alpha or 1, font)
end

function UI.textFit(element, value, x, y, maxWidth, font, color, alpha)
    UI.text(element, UI.fitText(value, font, maxWidth), x, y, font, color, alpha)
end

function UI.textCentreFit(element, value, x, y, maxWidth, font, color, alpha)
    UI.textCentre(element, UI.fitText(value, font, maxWidth), x, y, font, color, alpha)
end

function UI.inside(rect, x, y)
    return rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end
