--[[
    "psr_powerbank" client lua object — B42 rewrite (no CGlobalObject dependency)
--]]

local PSR = require "PSR/Utilities"

---@class PowerBankObject_Client
---@field luaSystem PowerbankSystem_Client
---@field x number
---@field y number
---@field z number
local PowerBank = {}
PowerBank.__index = PowerBank

function PowerBank:getSquare()
    return getSquare(self.x, self.y, self.z)
end

function PowerBank:getIsoObject()
    local square = self:getSquare()
    if not square then return nil end
    local objects = square:getSpecialObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if instanceof(obj, "IsoGenerator") and PSR.WorldUtil.getType(obj) == "PowerBank" then
            return obj
        end
    end
end

function PowerBank:fromModData(modData)
    self.on               = modData["on"]
    self.activated        = modData["activated"]
    self.batteries        = modData["batteries"]
    self.charge           = modData["charge"]
    self.maxcapacity      = modData["maxcapacity"]
    self.drain            = modData["drain"]
    self.npanels          = modData["npanels"]
    self.panels           = modData["panels"]
    self.lastHour         = modData["lastHour"]
    self.conGenerator     = modData["conGenerator"]
    self.PSR_linkedBanks  = modData["PSR_linkedBanks"]
end

function PowerBank:updateGenerator()
    -- Server is authoritative on generator state. Client does not modify it.
end

function PowerBank:updateFromIsoObject()
    local isoObject = self:getIsoObject()
    if isoObject then self:fromModData(isoObject:getModData()) end
end

local chargeSprites = {
    [0.10] = { "solarmod_tileset_01_1",  "solarmod_tileset_01_2",  "solarmod_tileset_01_3",  "solarmod_tileset_01_4",  "solarmod_tileset_01_5"  },
    [0.35] = { "solarmod_tileset_01_16", "solarmod_tileset_01_20", "solarmod_tileset_01_24", "solarmod_tileset_01_28", "solarmod_tileset_01_32" },
    [0.65] = { "solarmod_tileset_01_17", "solarmod_tileset_01_21", "solarmod_tileset_01_25", "solarmod_tileset_01_29", "solarmod_tileset_01_33" },
    [0.95] = { "solarmod_tileset_01_18", "solarmod_tileset_01_22", "solarmod_tileset_01_26", "solarmod_tileset_01_30", "solarmod_tileset_01_34" },
    [1.00] = { "solarmod_tileset_01_19", "solarmod_tileset_01_23", "solarmod_tileset_01_27", "solarmod_tileset_01_31", "solarmod_tileset_01_35" },
}
local chargeThresholds = { 0.10, 0.35, 0.65, 0.95, 1.00 }

function PowerBank:getSpriteForOverlay()
    local b = self.batteries or 0
    if b <= 0 then return nil end
    local mc = self.maxcapacity or 0
    local modCharge = mc > 0 and (self.charge or 0) / mc or 0
    local sprites
    for _, t in ipairs(chargeThresholds) do
        if modCharge < t then sprites = chargeSprites[t]; break end
    end
    sprites = sprites or chargeSprites[1.00]
    if b < 5 then return sprites[1]
    elseif b < 9  then return sprites[2]
    elseif b < 13 then return sprites[3]
    elseif b < 17 then return sprites[4]
    else return sprites[5] end
end

function PowerBank:updateSprite()
    local newSprite = self:getSpriteForOverlay()
    local isoObject = self:getIsoObject()
    if not isoObject then return end
    local attached = isoObject:getAttachedAnimSprite()
    if attached ~= nil then
        for i = 0, attached:size() - 1 do
            local s = attached:get(i)
            local n = s:getName()
            if n == newSprite then return end
            if n and string.find(n, "^solarmod_tileset_01_") then
                isoObject:RemoveAttachedAnim(i)
                break
            end
        end
    end
    if newSprite ~= nil then
        isoObject:addAttachedAnimSpriteByName(newSprite)
    end
end

function PowerBank:shouldDrain()
    if not self.on then return false end
    if self.conGenerator and self.conGenerator.ison then return false end
    if getWorld():isHydroPowerOn() then
        local square = self:getSquare()
        if square and not square:isOutside() then return false end
    end
    return true
end

-- True when the bank's drain is currently absorbed by the live city grid (mains power) rather than
-- by the batteries: bank on, no backup generator running, hydro power on, bank indoors. Mirrors the
-- grid branch of shouldDrain() above. The Details panel uses this to tell the player WHY the
-- batteries aren't dropping despite the displayed drain (we keep the drain figure as a sizing aid:
-- it shows what the solar array must cover once the grid goes down). Disappears on the world
-- power shutdown, the moment the bank actually starts carrying the load.
function PowerBank:coveredByMains()
    if not self.on then return false end
    if self.conGenerator and self.conGenerator.ison then return false end
    if not getWorld():isHydroPowerOn() then return false end
    local square = self:getSquare()
    return square ~= nil and not square:isOutside()
end

function PowerBank:getPanelStatus(panel)
    local x, y, z = panel:getX(), panel:getY(), panel:getZ()
    -- 2026-08-06 : THIRD copy of the same constant (client menu, client cursor, server). Found by
    -- grepping for the pattern after fixing the first two -- had it been missed, raising the
    -- sandbox option would have moved the menu to 40 tiles while this cursor stayed at 20, i.e.
    -- we would have MANUFACTURED the very client/server mismatch we set out to make impossible.
    local area = PSR.WorldUtil.getPanelConnectArea()
    if IsoUtils.DistanceToSquared(x, y, self.x, self.y) <= area.distance and math.abs(z - self.z) <= area.levels then
        for _, panelXYZ in ipairs(self.panels or {}) do
            if x == panelXYZ.x and y == panelXYZ.y and z == panelXYZ.z then return "connected" end
        end
        return "not connected"
    else
        return "far"
    end
end

function PowerBank:getPanelStatusOnSquare(square)
    local panel = PSR.WorldUtil.findTypeOnSquare(square, "Panel")
    if panel ~= nil then
        return panel, square:isOutside() and self:getPanelStatus(panel) or "indoors"
    end
    return nil, ""
end

return PowerBank
