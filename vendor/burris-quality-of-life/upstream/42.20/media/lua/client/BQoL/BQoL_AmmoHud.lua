--[[
    Burris Quality of Life -- rounds left in the equipped firearm, drawn as an
    icon-in-circle badge next to the main-hand slot.

    Vanilla draws no ammo indicator on the hotbar in 42.20. This appends one to
    ISEquippedItem:render, anchored to the same mainHand slot the weapon
    texture is drawn into (ISEquippedItem.lua:359, `hand.x/.y/.width/.height`).

    Earlier version drew bare outlined text, which read as noise against the
    weapon sprite. This instead draws a dark circular backdrop (the same
    media/ui/circle.png vanilla uses for radial menus), the ammo type's own
    item icon centred inside it, and the round count as a small badge
    overlapping the bottom-right, coloured by remaining fraction -- the icon
    identifies the caliber at a glance, the badge is legible against any
    background.

    Visibility is deliberately narrow: ranged HandWeapons with an actual
    magazine only. Bows, thrown weapons and melee all fail either isRanged()
    or the getMaxAmmo() > 0 guard, so nothing shows for them.
]]

require "BQoL/BQoL_Core"

local CIRCLE_TEXTURE = getTexture("media/ui/circle.png")
local CIRCLE_SIZE = 30
local ICON_SIZE = 20
local BADGE_FONT = UIFont.NewSmall

--- Ammo icon textures, keyed by item full type. Populated lazily; vanilla
--- gives no reason to prefetch every ammo type on boot.
local iconCache = {}

local function ammoIcon(itemKey)
    if not itemKey then return nil end

    local cached = iconCache[itemKey]
    if cached ~= nil then
        -- false is the cached "looked it up, there is no icon" result.
        return cached or nil
    end

    local ok, scriptItem = BQoL.safe(
        "AmmoHud.lookup:" .. itemKey,
        function() return ScriptManager.instance:getItem(itemKey) end)

    local texture = ok and scriptItem and scriptItem:getNormalTexture() or false
    iconCache[itemKey] = texture
    return texture or nil
end

local function ammoColour(fraction)
    if fraction > 0.5 then return 0.35, 0.9, 0.35 end
    if fraction > 0.25 then return 0.95, 0.7, 0.2 end
    return 0.95, 0.3, 0.25
end

local function drawBadge(self, hand, item)
    local maxAmmo = item:getMaxAmmo()
    if maxAmmo <= 0 then return end

    local ammoType = item:getAmmoType()
    local current = item:getCurrentAmmoCount()

    local cx = hand.x + hand.width - (CIRCLE_SIZE / 2)
    local cy = hand.y + hand.height - (CIRCLE_SIZE / 2)

    self:drawTextureScaled(CIRCLE_TEXTURE,
        cx - CIRCLE_SIZE / 2, cy - CIRCLE_SIZE / 2, CIRCLE_SIZE, CIRCLE_SIZE,
        0.75, 0, 0, 0)

    local icon = ammoType and ammoIcon(ammoType:getItemKey())
    if icon then
        self:drawTextureScaledAspect(icon,
            cx - ICON_SIZE / 2, cy - ICON_SIZE / 2, ICON_SIZE, ICON_SIZE,
            1, 1, 1, 1)
    end

    local text = tostring(current)
    local manager = getTextManager()
    local textW = manager:MeasureStringX(BADGE_FONT, text)
    local textH = manager:getFontHeight(BADGE_FONT)

    local bx = cx + CIRCLE_SIZE / 2 - textW - 2
    local by = cy + CIRCLE_SIZE / 2 - textH

    local r, g, b = ammoColour(current / maxAmmo)
    self:drawRect(bx - 2, by - 1, textW + 4, textH + 2, 0.7, 0, 0, 0)
    self:drawText(text, bx, by, r, g, b, 1, BADGE_FONT)
end

local function install()
    local originalRender = ISEquippedItem.render

    function ISEquippedItem:render()
        originalRender(self)

        local item = self.chr and self.chr:getPrimaryHandItem()
        if not item or not instanceof(item, "HandWeapon") or not item:isRanged() then
            return
        end

        BQoL.safe("AmmoHud.draw", drawBadge, self, self.mainHand, item)
    end
end

BQoL.feature{
    id = "AmmoHud",
    sandbox = "AmmoHudEnabled",
    init = install,
}
