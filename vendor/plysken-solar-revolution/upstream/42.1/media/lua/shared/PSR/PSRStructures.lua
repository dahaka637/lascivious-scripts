-- =============================================================================
-- PSRStructures.lua — résolution du footprint d'une structure PLAYER-BUILT
-- =============================================================================
-- Une extension construite par le joueur n'appartient à AUCUN IsoBuilding
-- (getBuilding()==nil) et n'a pas toujours de RoomDef. Le primitif fiable et
-- toujours présent est l'IsoWorldRegion (vérifié in-game : le build-out d'une
-- maison vanilla a getBuilding=nil, getRoom=nil, MAIS getIsoWorldRegion valide).
--
-- resolveSquares(ax,ay,az) = à partir d'une case-ancre, renvoie la liste des
-- cases {x,y,z} de la MÊME région player-built (BFS d'adjacence par identité de
-- région, borné). Fallback = petit rayon si l'ancre n'a pas de région (plancher
-- ouvert). Ne retient QUE des cases getBuilding()==nil (jamais un bâtiment vanilla
-- voisin → garde anti-grief, cohérent avec getDrainVanilla).
-- Shared (client + serveur) : le scan serveur ET la vérif d'éligibilité l'utilisent.
-- =============================================================================

local PSR = require "PSR/Utilities"

local Struct = {}

local MAX_SQUARES = 400   -- garde-fou dur (une extension raisonnable << 400 cases)
local FALLBACK_R  = 4     -- rayon de repli si l'ancre n'a pas d'IsoWorldRegion

local function regionId(reg)
    if not reg then return nil end
    if reg.getID then return reg:getID() end
    return reg
end

-- Renvoie une liste de { x, y, z } = les cases de la région player-built de l'ancre.
function Struct.resolveSquares(ax, ay, az)
    local result = {}
    local anchor = getSquare(ax, ay, az)
    if not anchor then return result end

    -- 🔴 2026-08-21 — DEUX MODES, décidés par l'ANCRE (chantier `peanuts`).
    -- Avant, les DEUX branches exigeaient `getBuilding() == nil` : ancrer sur une case de
    -- bâtiment de carte rejetait **l'ancre elle-même**, la liste sortait VIDE, et on
    -- enregistrait une connexion qui ne balayait aucune case. *Le menu aurait dit oui,
    -- l'action aurait réussi, et rien ne serait apparu dans le terminal.*
    --   · ancre SANS bâtiment  -> mode player-built : `b == nil`  (comportement HISTORIQUE, intact)
    --   · ancre AVEC bâtiment  -> mode carte        : `b == anchorBld`, on reste dans CE bâtiment
    -- ⚖️ Le mode carte n'élargit rien de plus que nécessaire : on ne sort jamais du bâtiment
    --    ancré, donc **la maison du voisin d'à côté reste hors de portée** même quand l'option
    --    sandbox est active. La garde anti-grief change de forme, elle ne disparaît pas.
    -- ⚠️ `MAX_SQUARES = 400` borne les deux modes. Un très grand bâtiment de carte peut donc
    --    être TRONQUÉ : c'est assumé et volontairement non silencieux — voir le compteur ci-dessous.
    local anchorBld = anchor:getBuilding()

    local function eligible(sq)
        if not sq then return false end
        local b = sq:getBuilding()
        if anchorBld == nil then return b == nil end
        return b == anchorBld
    end

    local region = anchor.getIsoWorldRegion and anchor:getIsoWorldRegion() or nil
    if region then
        local rid = regionId(region)
        local visited = {}
        local stack = { { ax, ay, az } }
        visited[ax .. "_" .. ay .. "_" .. az] = true
        while #stack > 0 and #result < MAX_SQUARES do
            local c = table.remove(stack)
            local cx, cy, cz = c[1], c[2], c[3]
            local sq = getSquare(cx, cy, cz)
            local sqReg = sq and sq.getIsoWorldRegion and sq:getIsoWorldRegion() or nil
            local sameRegion = sqReg and (sqReg == region or regionId(sqReg) == rid)
            if eligible(sq) and sameRegion then
                result[#result + 1] = { x = cx, y = cy, z = cz }
                local nb = {
                    { cx + 1, cy, cz }, { cx - 1, cy, cz },
                    { cx, cy + 1, cz }, { cx, cy - 1, cz },
                }
                for _, n in ipairs(nb) do
                    local k = n[1] .. "_" .. n[2] .. "_" .. n[3]
                    if not visited[k] then
                        visited[k] = true
                        stack[#stack + 1] = n
                    end
                end
            end
        end
        return result
    end

    -- Repli : pas de région (plancher totalement ouvert) → petit carré de cases player-built.
    for x = ax - FALLBACK_R, ax + FALLBACK_R do
        for y = ay - FALLBACK_R, ay + FALLBACK_R do
            local sq = getSquare(x, y, az)
            if eligible(sq) then
                result[#result + 1] = { x = x, y = y, z = az }
            end
        end
    end
    return result
end

PSR.Structures = Struct
return Struct
