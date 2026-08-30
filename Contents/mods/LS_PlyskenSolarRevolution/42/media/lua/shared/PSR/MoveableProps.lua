-- Placement restrictions + WallObject injection for PSR moveables.
-- Must be SHARED so it applies in both SERVER (cursor, actions) and CLIENT states.

local PSR_WALL_PANELS = {
    ["solarmod_tileset_01_6"] = "W",
    ["solarmod_tileset_01_7"] = "N",
}

local PSR_OUTDOOR_ONLY = {
    ["solarmod_tileset_01_8"]  = true,
    ["solarmod_tileset_01_9"]  = true,
    ["solarmod_tileset_01_10"] = true,
}

local PSR_INDOOR_ONLY = {
    ["solarmod_tileset_01_0"] = true,  -- PowerBank
}

local PSR = require "PSR/Utilities"

local origNew = ISMoveableSpriteProps.new
ISMoveableSpriteProps.new = function(spriteOrName)
    local o = origNew(spriteOrName)
    if o then
        local sn = o.spriteName
        if sn == "solarmod_tileset_01_6" then
            o.isMoveable    = true
            o.isMultiSprite = false
            o.type          = "WallObject"
            o.facing        = "W"
        elseif sn == "solarmod_tileset_01_7" then
            o.isMoveable    = true
            o.isMultiSprite = false
            o.type          = "WallObject"
            o.facing        = "N"
        end

        -- 🔧 `CustomItem` ABSENT DU TILEDEF (signal joueur Steam `puttheman`, 2026-08-04).
        -- Mesuré dans le binaire `solarmodtiledefs.tiles` : il ne déclare `CustomItem` qu'UNE
        -- fois — `PSR.PowerBank`. Aucun sprite de panneau ni le Failsafe n'en a.
        -- Or TOUT dépend de cette seule propriété côté vanilla (`ISMoveableSpriteProps`) :
        --   :135  `s.customItem = props:has("CustomItem") and props:get("CustomItem") or nil`
        --   :215  sans elle, le ramassage rend `instanceItem("Moveables."..spriteName)`
        --         => un moveable GÉNÉRIQUE, pas notre item. C'EST le défaut signalé, et il est ici.
        --
        -- 🔴 CORRECTION DE MON PROPRE DIAGNOSTIC (test in-game du 2026-08-04, Commandeur).
        -- J'avais écrit « un seul manque, ses DEUX symptômes » en croyant que `customItem`
        -- réparait aussi le démontage au sol, via `getDismantleRecipeFor` (:3527). **C'est FAUX.**
        -- Ce bloc du vanilla est gardé par `if deviceData and item.setDeviceData` (:3531) — il ne
        -- concerne QUE les appareils porteurs de `deviceData` (radios, TV). Un panneau n'en a pas
        -- ⇒ le chemin « recette » lui est **INATTEIGNABLE**, avec ou sans `customItem`, et
        -- l'exécution retombe sur le scrap générique par matériau (`getScrapItemsList`, :3554).
        -- ⇒ deux symptômes, DEUX causes.
        -- 📌 *Une explication qui couvre élégamment tous les symptômes est suspecte : c'est le
        --    test qui l'a cassée, pas la relecture — le code paraissait parfaitement cohérent.*
        --
        -- ⚖️ DÉCISION COMMANDEUR (2026-08-04) : on NE corrige PAS le démontage au sol, et on
        -- n'intercepte pas `getScrapItemsList`. Le comportement obtenu est celui du VANILLA pour
        -- tout moveable — **ramasser rend l'objet, démonter au sol rend des matériaux bruts** ;
        -- le joueur qui veut récupérer sa `Solar Panel (part)` ramasse le panneau puis passe par
        -- le menu de craft (`Reverse Solar Roof Tile` / `Split Solar Panel to parts`), ce qui
        -- fonctionne. ⇒ ne rien coder ici est cohérent avec le moteur, et la question de support
        -- se traite dans la DESCRIPTION, pas dans le code.
        --
        -- ⚠️ Le trou est PLUS LARGE que le signalement (il ne parlait que du panneau plat) :
        -- les sprites 6, 7, 8, 9, 10 ET 15 sont tous concernés. *La couverture s'arrête à l'item
        -- nommé et jamais à sa famille* — motif déjà payé plusieurs fois cette semaine.
        --
        -- On corrige ici plutôt que dans le `.tiles` : le binaire fonctionne, le regénérer pour
        -- une propriété ferait courir un risque à TOUS les sprites. La cause racine reste notée
        -- (RISKS) — c'est un choix de moindre risque, pas un oubli.
        if not o.customItem then
            local map = PSR and PSR.WorldUtil and PSR.WorldUtil.PSRPanelFullTypes
            local ft  = map and map[sn]
            if ft then o.customItem = ft end   -- dégrader plutôt que planter si la table manque
        end
    end
    return o
end

-- Checks both runtime square flags (player-built walls) and sprite tiledef properties (vanilla walls).
local function squareHasWall(sq, tag1, tag2)
    if not sq then return false end
    if sq:has(tag1) or sq:has(tag2) then return true end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local sp = objs:get(i):getSprite()
        if sp then
            local props = sp:getProperties()
            if props and (props:has(tag1) or props:has(tag2)) then return true end
        end
    end
    return false
end

local function psrCanPlaceWall(square, facing)
    if facing == "W" then
        return squareHasWall(square, "WallW", "WallNW")
    else -- "N"
        return squareHasWall(square, "WallN", "WallNW")
    end
end

-- "Vraie pièce" = pièce vanilla (getRoom) OU espace player-built ENCLOS (IsoWorldRegion:isEnclosed).
-- isOutside() seul est TROMPÉ par un simple toit (retourne false sous un toit même sans murs) → on
-- exige une vraie enceinte, sinon on pourrait poser une bank sous un abri à ciel ouvert muré/non muré.
-- Même primitive de détection que PFR (getRoomContext : getRoom / IsoWorldRegion enclose).
--
-- ⚠️ CE PRÉDICAT NE SUFFIT PAS À LUI SEUL POUR LA BANK — voir psrCheck plus bas : il dit "il y a des
-- MURS", pas "il y a un TOIT". Une enceinte player-built sans toit y répond `true` (MESURÉ in-game
-- le 2026-08-03, dédié : 4 murs sans toit ⇒ isEnclosed()=true ET isOutside()=true).
local function psrIsRealRoom(square)
    if square:getRoom() ~= nil then return true end
    if square.getIsoWorldRegion then
        local reg = square:getIsoWorldRegion()
        if reg and reg.isEnclosed and reg:isEnclosed() then return true end
    end
    return false
end

local function psrCheck(spriteName, square)
    if not square then return nil end
    local facing = PSR_WALL_PANELS[spriteName]
    if facing then
        -- 🚧 ANTI-EMPILEMENT DES PANNEAUX MURAUX (2026-08-11, demande Commandeur :
        --    « il faut juste qu'on puisse pas poser un panneau solaire ou une bank sur le meme endroit »).
        -- Les muraux sont les SEULS panneaux que le correctif « on delegue toujours au vanilla » ne
        -- couvre pas : ils se posent SUR un mur, et rien ne prouve qu'une case de mur passe
        -- `isFreeTile`/`IsHigh` -> deleguer pourrait les rendre IMPOSABLES, et leur filtre client est
        -- leur SEULE validation (`placeMoveable` surcharge n'emet pas `OnObjectAdded`). On pose donc
        -- un refus CIBLE plutot qu'une delegation : il ne peut pas refuser une pose legitime, puisque
        -- sur un mur nu aucun panneau n'est trouve.
        --
        -- 🔑 ON DISCRIMINE SUR LE SPRITE EXACT, PAS SUR « un panneau » : une case d'ANGLE porte un mur
        --    W *et* un mur N, et y poser un panneau W plus un panneau N est LEGITIME (deux murs
        --    differents, deux orientations). Un refus sur « findTypeOnSquare(square,"Panel") ~= nil »
        --    aurait casse ce cas -- c'est exactement le genre de correctif qui interdit du travail sain.
        -- ✅ Les muraux atterrissent bien dans les objets speciaux : `AddSpecialObject` plus bas.
        local special = square and square:getSpecialObjects()
        if special then
            for i = 0, special:size() - 1 do
                local obj = special:get(i)
                if obj and obj:getTextureName() == spriteName then return false end
            end
        end
        -- 🔴 LE CURSEUR EST LE SEUL FILTRE POUR LES PANNEAUX MURAUX (audit 2026-08-04).
        -- `placeMoveable` est surchargé plus bas pour ces deux sprites et n'émet volontairement
        -- PAS `OnObjectAdded` (voir le commentaire dédié) ⇒ le bloc de validation serveur de
        -- `PowerBankSystem_Server` ne s'exécute JAMAIS pour eux. Preuve corroborante : la clé
        -- `IGUI_PSR_WallPanel_NeedsWall` est traduite dans 27 langues et ne peut pas s'afficher.
        -- On ne testait ici que la présence d'un mur ⇒ le client était plus PERMISSIF que le
        -- serveur, sur les seuls sprites où le serveur ne peut plus servir de filet. C'est
        -- exactement l'invariant posé en v1.58 (« le critère client doit être au moins aussi
        -- strict que le serveur ») appliqué à la bank et jamais reporté ici.
        -- ⇒ On rejoue les TROIS conditions serveur, dans le même ordre.
        if not psrCanPlaceWall(square, facing) then return false end
        -- 2) plein ciel : tous les panneaux ont besoin de soleil.
        if not square:isOutside() then return false end
        -- 3) cohérence de rotation croisée : sans elle, il suffit de faire pivoter le curseur
        --    pour poser sous un toit. W en (x,y) ↔ (x+1,y-1) ; N en (x,y) ↔ (x-1,y+1).
        local cell = square:getCell()
        if cell then
            local x, y, z = square:getX(), square:getY(), square:getZ()
            local cx = (facing == "W") and x + 1 or x - 1
            local cy = (facing == "W") and y - 1 or y + 1
            local crossSq = cell:getGridSquare(cx, cy, z)
            if crossSq and not crossSq:isOutside() then return false end
        end
        return true
    end
    if PSR_OUTDOOR_ONLY[spriteName] then return square:isOutside() end
    -- Bank : MURS **ET** TOIT. Les deux moitiés sont nécessaires et aucune ne remplace l'autre —
    -- psrIsRealRoom() donne les murs, not isOutside() donne le toit.
    -- 🔴 2026-08-03, MESURÉ sur dédié : sans `not isOutside()`, une base murée SANS TOIT donnait un
    -- curseur VERT ici alors que le serveur la refuse (`PowerBankSystem_Server.lua`, `isOutside()`)
    -- ⇒ pose tentée, item consommé, refus serveur — c'est le signal joueur Discord du jour.
    -- 🔑 INVARIANT À TENIR : le critère CLIENT doit être **au moins aussi strict** que le critère
    -- SERVEUR. Toute divergence dans l'autre sens se paie en item détruit chez le joueur.
    -- Le serveur reste volontairement plus permissif (il ne teste que le toit) : il sert de FILET,
    -- et un filet plus large ne peut rien casser. Le durcir demanderait de prouver d'abord qu'un
    -- objet chargé depuis une save ne repasse pas par la branche de refus (non vérifié à ce jour).
    if PSR_INDOOR_ONLY[spriteName] then return psrIsRealRoom(square) and not square:isOutside() end
    return nil
end

--------------------------------------------------------------------------------
-- 🚧 NOTRE FILTRE RESTREINT, IL N'AUTORISE PAS (2026-08-11)
--------------------------------------------------------------------------------
-- ANCIENNE FORME, fautive : `if r ~= nil then return r end`. Des que psrCheck disait
-- « oui », `origCanPlace` n'etait JAMAIS appele et on sautait TOUTES les validations
-- vanilla. Ce qui sautait, verifie dans `shared/Moveables/ISMoveableSpriteProps.lua` :
--   :1499  `_square:has(IsoFlagType.water)`  <- la TOUTE PREMIERE ligne
--   :1607  `isVehicleIntersecting()`
--   :1609  pas de sol (`getFloor()`)
--   :1624/:1631  `isFreeTile()`  <- l'ANTI-EMPILEMENT, + arbres et BlocksPlacement
--   :1633  IsHigh / IsLow  ·  `isSquareAtTopOfStairs`
--
-- 🔴 CE QUE L'EMPILEMENT COUTAIT AU JOUEUR (chaine etablie par lecture, 2026-08-11) :
--    les panneaux sont enregistres PAR COORDONNEES (`ConnectPanel.lua:146`), et
--    `findTypeOnSquare` ne rend qu'UN objet par case => le panneau du dessous est
--    invisible a tout le mod. Pire, le garde anti-doublon de `checkPanels` est indexe
--    sur la CASE : les deux passages resolvent le MEME objet, donc il delie celui dont
--    il vient de garder l'entree => LES DEUX CONNEXIONS TOMBENT au tick de charge,
--    en silence. Le garde avait ete ecrit pour des ENTREES en double, pas des OBJETS.
--
-- ✅ FORME CORRECTE : on ne rend `false` que pour REFUSER, et on delegue TOUJOURS le
--    reste. *Autoriser, c'est remplacer le jugement de l'hote par le notre alors qu'on
--    ne sait pas ce qu'il verifie.* Meme correctif que PWS (audit du 2026-08-11), ou
--    le defaut avait ete trouve en premier : PSR est le patron dont PWS l'avait herite.
--
-- ⚠️ EXCEPTION ASSUMEE — LES PANNEAUX MURAUX GARDENT LE COURT-CIRCUIT. Ils se posent
--    SUR un mur, et rien ne prouve qu'une case de mur passe `isFreeTile`/`IsHigh` du
--    vanilla : deleguer pourrait les rendre IMPOSABLES. Leur filtre client est par
--    ailleurs leur SEULE validation (`placeMoveable` surcharge n'emet pas
--    `OnObjectAdded`, voir plus haut), donc un refus vanilla ne serait rattrape par
--    personne. Ils portent la meme forme et restent une dette ecrite, a instruire
--    avec une mesure en jeu -- pas a corriger en aveugle dans le meme lot.
--------------------------------------------------------------------------------

local origCanPlace = ISMoveableSpriteProps.canPlaceMoveable
function ISMoveableSpriteProps:canPlaceMoveable(character, square, item)
    local r = psrCheck(self.spriteName, square)
    if r == false then return false end
    if r == true and PSR_WALL_PANELS[self.spriteName] then return true end
    return origCanPlace(self, character, square, item)
end

local origCanPlaceInternal = ISMoveableSpriteProps.canPlaceMoveableInternal
function ISMoveableSpriteProps:canPlaceMoveableInternal(character, square, item, forceTypeObject)
    local r = psrCheck(self.spriteName, square)
    if r == false then return false end
    if r == true and PSR_WALL_PANELS[self.spriteName] then return true end
    return origCanPlaceInternal(self, character, square, item, forceTypeObject)
end

local origPlaceMoveable = ISMoveableSpriteProps.placeMoveable
function ISMoveableSpriteProps:placeMoveable(_character, _square, _origSpriteName, _forceAllow)
    if not PSR_WALL_PANELS[self.spriteName] then
        return origPlaceMoveable(self, _character, _square, _origSpriteName, _forceAllow)
    end
    if not (self.isMoveable and instanceof(_character,"IsoGameCharacter") and instanceof(_square,"IsoGridSquare")) then
        return
    end
    local item = self:findInInventory(_character, _origSpriteName)
    if item then
        if self:canPlaceMoveableInternal(_character, _square, item) then
            local north = (self.facing == "N" or self.facing == "S")
            local obj = IsoThumpable.new(getCell(), _square, self.spriteName, north, {})
            if obj then
                GameEntityFactory.TransferComponents(item, obj)
                _square:AddSpecialObject(obj, _square:getObjects():size())
                -- 2026-07-30 : transmitCompleteItemToServer() a ete RETIREE d'IsoObject en 42.20.
                -- L'appeler leve "Object tried to call nil" -> pose du panneau mural cassee pour un
                -- CLIENT de dedie (le SP est epargne : isClient() y est faux, d'ou le passage inapercu).
                -- Preuve directe : un mod tiers l'appelle sans garde et le jeu repond exactement ca.
                -- ATTENTION : ne PAS croire la JavaDoc, elle la liste encore (build anterieure).
                -- On GARDE l'appel derriere un test d'existence plutot que de le supprimer : le vanilla
                -- n'a pas d'equivalent client (`placeMoveableInternal` ne fait que la branche isServer),
                -- et on ne sait pas encore par quel chemin le serveur apprend CETTE pose - supprimer
                -- remplacerait un crash par une desync silencieuse (panneau invisible pour les autres).
                -- Degrade au lieu de planter ; si TIS reintroduit la methode, le comportement revient seul.
                if isClient() and obj.transmitCompleteItemToServer then obj:transmitCompleteItemToServer() end
                if isServer() and obj.transmitCompleteItemToClients then obj:transmitCompleteItemToClients() end
                -- triggerEvent("OnObjectAdded") intentionally omitted: vanilla Java handler
                -- removes IsoThumpable from wall tiles if sprite lacks WallW/WallN flags.
                _square:RecalcProperties()
                _square:RecalcAllWithNeighbours(true)
            end
            _character:getInventory():Remove(item)
            sendRemoveItemFromContainer(_character:getInventory(), item)
            ISMoveableCursor.clearCacheForAllPlayers()
        end
    else
        origPlaceMoveable(self, _character, _square, _origSpriteName, _forceAllow)
    end
end

-- walkAdj fails for wall tiles: getCorrectSquareForWall redirects WallW/WallN tiles to their
-- interior neighbor, so AdjacentFreeTileFinder returns nil. Walk player directly to the
-- exterior tile instead (x+1 for W, y+1 for N — confirmed by isOutside() on test data).
local origWalkToAndEquip = ISMoveableSpriteProps.walkToAndEquip
function ISMoveableSpriteProps:walkToAndEquip(character, square, mode, origSpriteName)
    if mode == "place" and PSR_WALL_PANELS[self.spriteName] then
        local cell = square:getCell()
        local x, y, z = square:getX(), square:getY(), square:getZ()
        local extSq
        if self.facing == "W" then
            extSq = cell:getGridSquare(x + 1, y, z)
        else -- "N"
            extSq = cell:getGridSquare(x, y + 1, z)
        end
        if extSq then
            ISTimedActionQueue.clear(character)
            ISTimedActionQueue.add(ISWalkToTimedAction:new(character, extSq))
            return true
        end
    end
    return origWalkToAndEquip(self, character, square, mode, origSpriteName)
end
