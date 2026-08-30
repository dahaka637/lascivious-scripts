-- Lascivious Factions System - tile-selection tool interface.
-- This is the boundary the partner's external tile-selection tool will call to
-- turn a player's on-screen selection into a faction land claim. For now it
-- just forwards a set of rectangles to the server as a "claim" intent, plus a
-- debug helper that fabricates a selection around the player so the whole flow
-- can be exercised before the real tool is wired in.

require "LFS_Shared"

local FF = LasciviousFactionsSystem

-- Public entry point for the external tool.
--   player : IsoPlayer making the claim
--   rects  : array of {x1,y1,x2,y2} tile rectangles describing the selection
-- The server validates size/overlap/membership and either applies or rejects.
function FF.requestClaim(player, rects)
    if not (player and rects and #rects > 0) then
        return
    end
    local normalised = {}
    for i = 1, #rects do
        normalised[i] = FF.normaliseRect(rects[i])
    end
    normalised = FF.canonicaliseClaimRects(normalised)
    sendClientCommand(player, FF.MODULE, "claim", { rects = normalised })
end

-- Debug placeholder: build a square selection of `size` tiles centred on the
-- player and submit it as if it came from the real tool. Wired to a console
-- command in LFS_Client.
function FF.debugClaimAroundPlayer(player, size)
    if not player then return end
    size = math.max(1, math.min(1000, math.floor(tonumber(size) or 20)))
    local half = math.floor(size / 2)
    local x, y = math.floor(player:getX()), math.floor(player:getY())
    -- Inclusive coordinates: x2=x1+size-1. The old symmetric formula created
    -- 21x21 tiles when the caller requested an even 20x20 selection.
    local x1, y1 = x - half, y - half
    local rect = { x1, y1, x1 + size - 1, y1 + size - 1 }
    FF.requestClaim(player, { rect })
end
