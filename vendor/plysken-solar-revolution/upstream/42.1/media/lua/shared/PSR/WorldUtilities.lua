---@class PSR
local PSR = require "PSR/Utilities"

local WorldUtil = {}

---@alias PSRType
---| `PowerBank`
---| `Panel`
---| `Failsafe`

WorldUtil.PSRTypes = {
    solarmod_tileset_01_0 = "PowerBank",
    solarmod_tileset_01_6 = "Panel",
    solarmod_tileset_01_7 = "Panel",
    solarmod_tileset_01_8 = "Panel",
    solarmod_tileset_01_9 = "Panel",
    solarmod_tileset_01_10 = "Panel",
    solarmod_tileset_01_15 = "Failsafe",
}

-- Fallback fullType when getSprite() unavailable (server context / early callback)
WorldUtil.PSRFullTypes = {
    PowerBank = "PSR.PowerBank",
    Panel     = "PSR.Panel",
    Failsafe  = "PSR.Failsafe",
}

-- Sprite → inventory item fullType for panels (used when rejecting placement)
WorldUtil.PSRPanelFullTypes = {
    ["solarmod_tileset_01_6"]  = "PSR.SolarPanelWall",
    ["solarmod_tileset_01_7"]  = "PSR.SolarPanelWall",
    ["solarmod_tileset_01_8"]  = "PSR.SolarPanelFlat",
    ["solarmod_tileset_01_9"]  = "PSR.SolarPanelMounted",
    -- 🔴 CORRIGÉ 2026-08-04 (audit) : valait `PSR.SolarPanelFlat`, c'était FAUX.
    -- Preuve dans le tiledef binaire : `_9` et `_10` sont des JUMEAUX — `CustomName = Solar Panel`,
    -- `GroupName = Floor Mounted`, `IsLow`, `PickUpWeight = 50` (= 5.0, le poids de SolarPanelMounted) —
    -- seul le `Facing` diffère (W pour `_9`, N pour `_10`) : c'est la rotation du curseur de pose.
    -- `_8`, lui, est `CustomName = Solar Roof Tile`, sans GroupName, `PickUpWeight = 40` : c'est le Flat.
    -- ⚠️ L'erreur était DORMANTE tant que cette table ne servait qu'au remboursement après refus de
    -- pose ; en la branchant sur le RAMASSAGE (correctif `customItem`, le même jour), elle devenait une
    -- perte de matériaux quotidienne : ramasser un panneau au sol orienté N rendait un *Flat*, dont le
    -- démontage ne rend ni les 4 MetalBar ni les 4 vis du Mounted.
    -- 📌 *Réutiliser une table, c'est hériter de ses erreurs — y compris de celles que son ancien
    -- usage rendait invisibles.*
    ["solarmod_tileset_01_10"] = "PSR.SolarPanelMounted",
    -- Le Failsafe partage exactement le même défaut de tiledef (aucun `CustomItem`) : il est donc
    -- ici pour la même raison que les panneaux, et cette table est désormais LE point unique
    -- « sprite → item d'inventaire ». Ne pas en refaire une seconde ailleurs.
    ["solarmod_tileset_01_15"] = "PSR.SolarFailsafe",
}

---return type of solar object
---@param isoObject IsoObject
---@return PSRType
function WorldUtil.getType(isoObject)
    if not isoObject then return nil end
    return WorldUtil.PSRTypes[isoObject:getTextureName()]
end

---@param isoObject IsoObject
---@param modType PSRType
---@return boolean
function WorldUtil.objectIsType(isoObject, modType)
    if not isoObject then return false end
    return WorldUtil.PSRTypes[isoObject:getTextureName()] == modType
end

---@param level number Electical skill level
---@return table
-- Backup generator <-> battery bank connection range. `level` is the caller's default basis :
-- Electrician skill for a manual plug (PBSystem:onPlugGenerator) or 3 for the placement-time
-- auto-reconnect (PowerBank:autoConnectBackup). Sandbox PSR.BackupConnectRange > 0 OVERRIDES it
-- with a fixed tile radius (0 = keep the skill / auto default = unchanged behaviour). Single read
-- point : the override flows to BOTH server paths AND the client "Gen in range" UI for free.
-- MP-safe : pure read of a synced SandboxVar, no new state/messages ; the authoritative connection
-- runs server-side (server SandboxVars), the client UI reads the same synced value. Player request
-- (v1.43) : wire a backup genset across a large base regardless of skill. The failsafe operation is
-- distance-agnostic (only checks a Failsafe tile on the generator square), so a long-range link works.
function WorldUtil.getValidBackupArea(level)
    local override = SandboxVars and SandboxVars.PSR and SandboxVars.PSR.BackupConnectRange
    if type(override) == "number" and override > 0 then
        level = override
    end
    -- Vertical reach = guaranteed minimum of +/-1 floor, DECOUPLED from skill (player report : bank on
    -- the 2nd floor, backup generator on the 1st -> never detected). Previously levels was 0 at
    -- Electricity <= 5, so the z-scan only looked at the bank's own floor and a stacked genset was
    -- invisible. Horizontal radius/distance still scale with skill/override exactly as before.
    --
    -- SANDBOX `BackupConnectFloors` (signal `Bee [TiT]`, 2026-08-08 : *"the failsafe doesn't seem to
    -- work if the generator is on the roof of a building (3 stories high)"*). The floor of 1 WAS the
    -- bug : a rooftop genset 3 levels above the bank could never be seen, and nothing told the player
    -- why -- the panel just says "0 generators in range". His diagnosis was exact.
    --
    -- 🧬 THIS IS THE TWIN OF `PanelConnectFloors` BELOW, AND WE MISSED IT FOR A DAY : we fixed the
    -- panels' vertical reach on 2026-08-07 (signal `Sitesee`) and left the generator's at 1, in the
    -- function directly above it, in the same file. *Fix a case, sweep its family.*
    --
    -- FLOOR OF 1 IS DELIBERATE, DO NOT LOWER IT : same invariant as every other reach option in this
    -- file -- it may only ever EXTEND. Dropping to 0 would confine the scan to the bank's own floor
    -- and silently unplug generators players already had connected.
    -- READ INSIDE THE FUNCTION, never at file load (see feedback-sandboxvars-lu-au-chargement).
    -- MAX OF 8 mirrors `getPanelConnectArea` : a chosen bound, not a measured one.
    -- 🔴 RAISING `levels` ALONE WOULD HAVE SHIPPED A DEAD OPTION. Found by sweeping the callers,
    -- not by reading this function : BOTH consumers (`getPowerBanksInArea` and
    -- `PowerBankObject_Server:autoConnectBackup`) gate every square on `IsoUtils.DistanceToSquared`
    -- in its **6-argument 3D form**, so the vertical gap is CHARGED TO THE SAME BUDGET as the
    -- horizontal one. `levels` only widens the z-loop ; `distance` decides what survives it.
    -- At skill 3 the budget is 11.25 -> a genset 3 floors up costs 9 on its own, and any horizontal
    -- offset beyond ~1 tile pushes it out. The option would have "worked" only straight overhead.
    -- ⇒ give the vertical reach its OWN budget on top, so the two axes stop competing.
    -- STILL AN EXTENSION ONLY : at the default of 1 this adds exactly +1 to a budget that was
    -- already there, so no previously-connected generator can ever fall out of range.
    local floors = SandboxVars and SandboxVars.PSR and SandboxVars.PSR.BackupConnectFloors
    if type(floors) ~= "number" or floors < 1 then floors = 1 end
    if floors > 8 then floors = 8 end
    return { radius = level, levels = floors, distance = math.pow(level, 2) * 1.25 + math.pow(floors, 2) }
end

-- Solar panel <-> battery bank CONNECTION range. SINGLE READ POINT for both sides.
--
-- WHY THIS EXISTS (2026-08-06) : the radius was written TWICE as a bare constant -- client
-- `PowerBankSystem_Client.canConnectPanelTo` (contextual menu on the panel) and server
-- `PowerBank:getPanelStatus` (cursor from the bank + the authoritative `ConnectPanel:complete`).
-- Both read `<= 400.0` and `<= 3`. They happened to agree, so nothing was broken -- but a twin
-- constant only stays correct until someone edits one of the two. Making it one function is the
-- fix ; the sandbox option is what the single point then buys us for free.
--
-- MP-SAFE : pure read of a synced SandboxVar, exactly like `getValidBackupArea` above. The
-- authoritative check runs server-side and the client UI reads the same synced value, so both
-- sides stay in agreement by construction -- the invariant "client at least as strict as the
-- server" cannot drift, because there is only one source left.
--
-- READ INSIDE THE FUNCTION, NEVER AT FILE LOAD : a mod's Lua boots with the LuaManager, long
-- before `IsoWorld.init()` loads the world's SandboxVars. A file-level read would silently fall
-- back to the default for the whole session (see feedback-sandboxvars-lu-au-chargement).
--
-- FLOOR OF 20 IS DELIBERATE, DO NOT LOWER IT : `PowerBank:checkPanels` drops every panel whose
-- status is no longer "connected". If this range could shrink, lowering the option would silently
-- DISCONNECT panels the player had already wired up. The option may only ever extend the reach.
-- VERTICAL REACH — same invariant as the radius, for the same reason (signal `Sitesee`, 2026-08-07 :
-- *« solar pannels doesn't connect farther then 3 floors, but my bunker was under 4 floors »*).
-- The old value of 3 was hard-coded and our own sandbox tooltip advertised it, so his diagnosis was
-- right : he did not hit a bug, he hit the documented limit. FLOOR OF 3 IS DELIBERATE — lowering it
-- would let `checkPanels` silently drop panels the player had already wired up, exactly like the
-- radius. **This option may only ever EXTEND the reach, never shrink it.**
-- ⚠️ MAX OF 8 IS A CHOSEN BOUND, NOT A MEASURED ONE : the JavaDoc for `IsoCell` (read 2026-08-07)
-- exposes `getMaxFloors()`, `getMinZ()`, `getMaxZ()`, `getMaxHeight()` and a `minHeight` field —
-- so negative z is architecturally supported — but it documents **no numeric bound whatsoever**.
-- 8 is deliberately conservative : the scan is a cube, so each extra floor costs 2 more z-slices
-- across the whole radius. Raise it only against a real measurement, never against the doc.
function WorldUtil.getPanelConnectArea()
    local r = SandboxVars and SandboxVars.PSR and SandboxVars.PSR.PanelConnectRange
    if type(r) ~= "number" or r < 20 then r = 20 end
    if r > 40 then r = 40 end
    local f = SandboxVars and SandboxVars.PSR and SandboxVars.PSR.PanelConnectFloors
    if type(f) ~= "number" or f < 3 then f = 3 end
    if f > 8 then f = 8 end
    -- `distance` stays r*r on purpose, and it is a **purely HORIZONTAL** budget.
    -- ✅ MEASURED at the call sites (2026-08-07), not deduced : the two panel-connect checks use the
    -- 2D form plus a SEPARATE vertical test —
    --   `PowerBankObject_Server:941`  IsoUtils.DistanceToSquared(x, y, self.x, self.y) <= area.distance
    --                                 and math.abs(z - self.z) <= area.levels
    --   `PowerBankSystem_Client:198`  dx*dx + dy*dy <= area.distance and abs(z - pb.z) <= area.levels
    -- ⇒ **the two axes are fully independent** : raising `levels` costs nothing from the horizontal
    -- budget, and `distance` must therefore never be made to depend on `f`.
    -- ⚠️ WHY THIS COMMENT EXISTS : the JavaDoc (`zombie.iso.IsoUtils`) shows `DistanceToSquared` in a
    -- 4-arg **2D** form and a 6-arg **3D** form, and I first assumed our callers used the 3D one — they
    -- do not. `WorldUtil.getPowerBanksInArea` below DOES use the 6-arg 3D form, which is exactly what
    -- makes the mix-up easy. *Confirming that an API form EXISTS says nothing about which form WE call.*
    -- Making it depend on `f` would quietly widen the HORIZONTAL reach too.
    return { radius = r, levels = f, distance = r * r }
end

---@param square IsoGridSquare
---@param radius number
---@param zLevels number
---@param distance number
---@return table<any,PowerBankObject_Server>
function WorldUtil.getPowerBanksInArea(square, radius, zLevels, distance)
    local all = {}
    local x = square:getX()
    local y = square:getY()
    local z = square:getZ()
    for ix = x - radius, x + radius do
        for iy = y - radius, y + radius do
            for iz = z - zLevels, z + zLevels do
                local isquare = IsoUtils.DistanceToSquared(x,y,z,ix,iy,iz) <= distance and getSquare(ix, iy, iz)
                local pb
                if isquare then
                    -- 🔴 GARDE 3-CONTEXTES (audit 2026-08-04). Valait `if isClient() then`.
                    -- L'unique appelant est `PBSystem:onPlugGenerator`, un chemin SERVEUR, qui
                    -- enchaine sur `pb:connectBackupGenerator(...)` — methode qui n'existe QUE sur
                    -- `PowerBankObject_Server`. Sur un HOTE COOP (`isClient()` ET `isServer()`
                    -- vrais), l'ancienne condition rendait des objets CLIENT ⇒ « Object tried to
                    -- call nil ». Le defaut etait masque par la garde de `Patches.lua`, qui tuait
                    -- l'appelant sur ce meme contexte : corriger l'un sans l'autre transformait
                    -- une fonction muette en crash. Les deux le sont dans le meme geste.
                    if isClient() and not isServer() then
                        pb = PSR.PBSystem_Client:getLuaObjectOnSquare(isquare)
                    else
                        pb = PSR.PBSystem_Server:getLuaObjectOnSquare(isquare)
                    end
                end
                if pb ~= nil then
                    table.insert(all,pb)
                end
            end
        end
    end
    return all
end

function WorldUtil.findOnSquare(square,sprite)
    if not square then return nil end
    local special = square:getSpecialObjects()
    for i = 0, special:size()-1 do
        local obj = special:get(i)
        if obj:getTextureName() == sprite then
            return obj
        end
    end
end

---@param square IsoGridSquare
---@param type string
---@return IsoObject?
function WorldUtil.findTypeOnSquare(square, type)
    if not square then return nil end
    local special = square:getSpecialObjects()
    for i = 0, special:size() - 1 do
        local obj = special:get(i)
        if WorldUtil.PSRTypes[obj:getTextureName()] == type then
            return obj
        end
    end
    return nil
end

---@param square IsoGridSquare
---@param spriteName string
---@param index number
---@param fullSpawn boolean
---@return IsoGenerator
function WorldUtil.placePowerBank(square, spriteName, index, fullSpawn)
    -- Always resolve fullType from our known mapping — getProperties():Is/Val unreliable in B42
    local psrType = WorldUtil.PSRTypes[spriteName]
    local fullType = (psrType and WorldUtil.PSRFullTypes[psrType]) or ("Moveables." .. spriteName)

    local sprite = getSprite(spriteName)
    local generator = IsoGenerator.new(square:getCell())
    if sprite then generator:setSprite(sprite) end
    generator:setSquare(square)
    generator:getModData().generatorFullType = fullType

    if fullSpawn then
        square:AddSpecialObject(generator, index)
        if sprite then generator:createContainersFromSpriteProperties() end
        local container = generator:getContainer()
        if container then
            container:setExplored(true)
            -- Remove the PSR.PowerBank stub added by the tiledef CustomItem (not a battery)
            local items = container:getItems()
            for i = items:size() - 1, 0, -1 do container:Remove(items:get(i)) end
        end
        generator:transmitCompleteItemToClients()
        generator:setCondition(100)
        generator:setFuel(100)
        generator:setConnected(true)
        generator:getCell():addToProcessIsoObjectRemove(generator)
        triggerEvent("OnObjectAdded", generator)
    end

    return generator
end

---@param isoObject IsoObject
---@return IsoGenerator?
function WorldUtil.replaceIsoObjectWithGenerator(isoObject)
    local square = isoObject:getSquare()
    local index = isoObject:getObjectIndex()
    if not square or index == -1 then return end
    local spriteName = isoObject:getTextureName()
    square:transmitRemoveItemFromSquare(isoObject)
    return WorldUtil.placePowerBank(square, spriteName, index, true)
end

---Check if a single square has a PLAYER-BUILT wall (IsoThumpable).
---⚠️ NE detecte PAS les murs de carte — voir la note ci-dessous, la doc precedente le promettait a tort.
---@param sq IsoGridSquare
---@return boolean
function WorldUtil.squareHasWall(sq)
    if not sq then return false end
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        -- ❌ `instanceof(obj, "IsoWall")` RETIRE 2026-08-04 : TOUJOURS FAUX. La classe `IsoWall`
        -- n'existe pas en 42.20 (verifie dans projectzomboid.jar ; seul `IsoWallBloodSplat` porte
        -- ce prefixe), et `instanceof` sur un nom inconnu rend `false` EN SILENCE, sans erreur.
        -- ⚠️ CONSEQUENCE REELLE : cette fonction ne voit QUE les murs construits par le joueur.
        -- Les murs de carte B42 sont des `IsoObject` nus porteurs des drapeaux `WallW`/`WallN` —
        -- il faudrait tester l'ARETE de la case pour les detecter. La moitie « murs de carte »
        -- n'a donc jamais fonctionne : on le DOCUMENTE au lieu de laisser un test mort le faire
        -- croire. (Sans effet aujourd'hui : l'unique appelant est la validation serveur des
        -- panneaux muraux, elle-meme inatteignable — cf. le correctif du curseur, vague 1.)
        if instanceof(obj, "IsoThumpable") then return true end
    end
    return false
end


---Liste de joueurs utilisable DANS LES TROIS CONTEXTES (solo / hote coop / dedie).
---
---⚠️ `IsoPlayer.getPlayers()` rend un `ArrayList<IsoPlayer>` (JavaDoc B42) mais la JavaDoc ne dit
---PAS ce qu'il contient. Deux indices convergents disent "joueurs LOCAUX de la machine" (splitscreen,
---4 max) et non "joueurs connectes" : la famille statique voisine est locale par nature
---(`IsoPlayer[] players`, `numPlayers`, `getPlayer(playerIndex)`, `getLocalPlayerByOnlineID`), et le
---Lua serveur vanilla n'utilise jamais `getPlayers()` pour joindre des joueurs : il prend
---`getOnlinePlayers()` (ClientCommands.lua:628, forageServer.lua:463, XpUpdate.lua:300).
---=> sur un dedie headless la liste serait VIDE, donc refus muet + item mange.
---⚠️ NON PROUVE EN JEU a ce jour (2026-08-03) : c'est une deduction, pas une mesure. Le correctif
---est neanmoins juste dans les deux cas, puisqu'il ne fait qu'ajouter une source avant le repli.
---
---`getOnlinePlayers()` rend une liste VIDE en solo -> le fallback est OBLIGATOIRE, jamais l'un seul.
---@return table? liste de joueurs (ArrayList Java : :size() / :get(i))
local function psrPlayerList()
    if getOnlinePlayers then
        local online = getOnlinePlayers()
        if online and online:size() > 0 then return online end
    end
    return IsoPlayer.getPlayers()
end

---Return an item to the nearest player within 5 squares (used when placement is rejected).
---@param square IsoGridSquare
---@param fullType string  e.g. "PSR.SolarPanelWall"
function WorldUtil.returnItemToNearbyPlayer(square, fullType)
    local players = psrPlayerList()
    if not players then return end
    local sx, sy, sz = square:getX(), square:getY(), square:getZ()
    local closest, closestDist = nil, math.huge
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then
            local d = IsoUtils.DistanceToSquared(p:getX(), p:getY(), p:getZ(), sx, sy, sz)
            if d < closestDist then closest, closestDist = p, d end
        end
    end
    if closest and closestDist <= 25 then
        local inv = closest:getInventory()
        local item = inv and inv:AddItem(fullType)
        -- ⚠️ L'inventaire est SERVER-AUTHORITATIVE : un AddItem cote serveur n'est pas pousse au
        -- client, l'item n'apparait jamais chez lui. Idiome vanilla = AddItem PUIS
        -- sendAddItemToContainer (FishingNet.lua:74, camping_tent.lua:194). Meme defaut, meme
        -- correctif que PIP v1.2.7 : le mod savait CONSOMMER un item, pas en RENDRE un.
        if item and sendAddItemToContainer then sendAddItemToContainer(inv, item) end
    end
end

---Send a notification IGUI key to all players within ~5 squares of the given square.
---
--- 🔴🔴 CORRIGÉ LE 2026-08-16 — CETTE FONCTION ÉTAIT MUETTE EN SOLO, ET SON COMMENTAIRE L'A CACHÉ.
---    L'ancienne ligne disait : *« Uses sendServerCommand so it works in both SP and MP »*.
--- 📚 Doc lue (bytecode 42.20, `zombie.Lua.LuaManager$GlobalObject`) :
---      `sendServerCommand` : `getstatic GameServer.server` → `ifeq` → `return`
---    ⇒ **no-op DUR dès qu'on n'est pas un serveur**. En solo, `GameServer.server` est faux : rien
---    n'était envoyé, rien n'était affiché.
--- 💥 Conséquence, chez la majorité des joueurs : les **quatre** refus de pose
---    (`PowerBank_IndoorsOnly`, `Panel_OutdoorOnly` ×2, `WallPanel_NeedsWall`) rendaient l'item
---    **sans jamais dire pourquoi**. Le curseur rougit, l'objet revient, et le joueur invente une
---    règle : *« ça ne se pose pas dans une pièce à deux portes »* (`Tempo`, 15/08),
---    *« ça ne se construit qu'au rez-de-chaussée »* (`killaZoo`, 16/08). Aucune des deux n'est
---    notre règle — ils ont deviné, parce qu'on ne leur a rien dit.
--- 🔑 *Un refus muet est un bug qui ne se signale pas* : il ne produit pas de rapport, il produit
---    de la désinformation que les joueurs se transmettent entre eux.
--- ⚙️ Routage 3 contextes **recopié de `ConnectStructure.lua:79-89`** — la forme juste existait
---    déjà dans ce mod, elle n'avait pas été portée ici. *Corriger un cas, balayer sa famille.*
---@param square IsoGridSquare
---@param msgKey string  IGUI translation key
function WorldUtil.notifyNearbyPlayers(square, msgKey)
    local players = psrPlayerList()
    if not players then return end
    local sx, sy, sz = square:getX(), square:getY(), square:getZ()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and IsoUtils.DistanceToSquared(p:getX(), p:getY(), p:getZ(), sx, sy, sz) <= 25 then
            -- Serveur (dédié ou hôte coop) ET destinataire distant ⇒ commande réseau.
            -- Sinon (solo, ou joueur local de l'hôte) ⇒ halo local, seul chemin qui parle ici.
            if isServer() and p ~= getSpecificPlayer(0) then
                sendServerCommand(p, "PSR", "notification", { key = msgKey })
            elseif HaloTextHelper and HaloTextHelper.addBadText then
                HaloTextHelper.addBadText(p, getText(msgKey))
            end
        end
    end
end

---Send a notification IGUI key to every player currently inside the given building.
---
--- 🧬 JUMEAU DE `notifyNearbyPlayers`, ET C'EST DÉLIBÉRÉ : même routage 3 contextes, **autre
---    sélecteur**. La distance ne convient pas ici — le danger est à l'échelle du BÂTIMENT
---    (`IsoBuilding.isToxic` est un drapeau par bâtiment), et la victime type dort dans une
---    autre pièce que celle où tourne le générateur. Un rayon de 5 cases l'aurait manquée.
--- 🔑 *Choisir le rayon parce que la fonction voisine l'utilise, c'est hériter d'un sélecteur
---    au lieu de le choisir.* Le sélecteur doit décrire QUI EST EXPOSÉ, pas qui est proche.
--- ⚖️ Le routage lui-même n'est PAS redupliqué par accident : il est recopié parce que
---    `sendServerCommand` est un no-op dur hors serveur (bytecode 42.20) — la leçon du 16/08
---    ci-dessus. Si un 3ᵉ sélecteur apparaît, extraire le routage en point unique.
---@param building IsoBuilding
---@param msgKey string  IGUI translation key
function WorldUtil.notifyPlayersInBuilding(building, msgKey)
    if not building then return end
    local players = psrPlayerList()
    if not players then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        local sq = p and p.getSquare and p:getSquare() or nil
        if sq and sq:getBuilding() == building then
            if isServer() and p ~= getSpecificPlayer(0) then
                sendServerCommand(p, "PSR", "notification", { key = msgKey })
            elseif HaloTextHelper and HaloTextHelper.addBadText then
                HaloTextHelper.addBadText(p, getText(msgKey))
            end
        end
    end
end

---Returns squares adjacent (N/S/E/W, same z) that contain a PSR PowerBank.
---@param x number
---@param y number
---@param z number
---@return IsoGridSquare[]
function WorldUtil.getAdjacentBankSquares(x, y, z)
    local result = {}
    local offsets = { {-1,0}, {1,0}, {0,-1}, {0,1} }
    for _, off in ipairs(offsets) do
        local sq = getSquare(x + off[1], y + off[2], z)
        if sq and WorldUtil.findTypeOnSquare(sq, "PowerBank") then
            table.insert(result, sq)
        end
    end
    return result
end

---Returns a compass direction string from (x1,y1) toward (x2,y2).
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return string
function WorldUtil.getDirection(x1, y1, x2, y2)
    if x2 < x1 then return "W"
    elseif x2 > x1 then return "E"
    elseif y2 < y1 then return "N"
    else return "S" end
end

---Retourne l'IsoObject de l'ordinateur REELLEMENT lie a `pb`, en verifiant sa reference EN RETOUR.
---Une case qui porte un autre desktop (ou plus rien du tout) ne compte pas : `pb.PSR_computer` est
---une simple coordonnee, elle ne prouve pas qu'un ordinateur lie s'y trouve encore.
---
---⚠️ Le second retour distingue « la case dit NON » de « on ne sait pas » : si le chunk n'est pas
---charge, `getSquare` rend nil et l'absence n'est PAS une preuve. L'appelant ne doit rien effacer
---dans ce cas — un nettoyage destructif ne doit jamais agir sur une absence d'information
---(regle payee sur PFR : faux degel = perte de nourriture definitive).
---@param pb table PowerBankObject
---@return IsoObject|nil computer  l'ordinateur lie, ou nil
---@return boolean squareKnown     true si la case etait chargee et a donc pu repondre
function WorldUtil.findLinkedComputer(pb)
    local c = pb and pb.PSR_computer
    if not c then return nil, true end
    local sq = getSquare(c.x, c.y, c.z)
    if not sq then return nil, false end          -- chunk non charge : on NE SAIT PAS
    local objs = sq:getObjects()
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        local lb = obj and obj:getModData().PSR_linkedBank
        if lb and lb.x == pb.x and lb.y == pb.y and lb.z == pb.z then
            return obj, true
        end
    end
    return nil, true
end

---Efface `pb.PSR_computer` s'il est PROUVE perime (case chargee, aucun ordinateur portant la
---reference en retour). Ne fait rien tant qu'on ne peut pas prouver l'absence.
---@param pb table PowerBankObject
---@return boolean cleared
function WorldUtil.healComputerLink(pb)
    if not pb or not pb.PSR_computer then return false end
    local comp, squareKnown = WorldUtil.findLinkedComputer(pb)
    if comp or not squareKnown then return false end
    pb.PSR_computer = nil
    if pb.saveData then pb:saveData(true) end
    return true
end

---Élague les extensions manuelles (`PSR_manualStructures`) dont la structure a été DÉMOLIE.
---
---🐛 Le défaut : `ConnectStructure` retire proprement une entrée quand le joueur **déconnecte**,
---et `OnObjectAboutToBeRemoved` nettoie quand la **bank** disparaît — mais **rien** ne couvre le cas
---où c'est la **structure** qui est détruite. L'entrée survivait alors indéfiniment : la bank
---continuait de balayer et de **facturer** une extension qui n'existe plus, et la liste grossissait
---sans borne dans la save.
---
---🔒 **Preuve POSITIVE exigée pour effacer** (même discipline que `healComputerLink` ci-dessus, et
---   que le faux dégel de PFR) : si la case de l'ancre n'est pas chargée, `getSquare` rend `nil` et
---   **l'absence n'est pas une preuve** ⇒ on ne touche à rien. On n'élague que si la case est bien
---   là ET qu'aucun objet dessus ne porte plus notre tag `PSR_structBank`.
---
---⚖️ **Arbitrage assumé** : le critère est le tag sur la case de **l'ANCRE** — celle que le joueur a
---   cliquée — et non sur toute la région (la résoudre coûterait un BFS jusqu'à 400 cases à chaque
---   tick de drain). Conséquence : détruire spécifiquement la tuile d'ancrage rompt la connexion,
---   même si le reste de l'extension tient. C'est **récupérable en un clic** (reconnecter), là où le
---   comportement actuel facture une ruine pour toujours.
--- 🔑 POINT UNIQUE du prédicat « cet objet peut-il porter l'ancre d'une structure connectée ? »
--- (2026-08-21). Il a **trois** consommateurs — `ConnectStructure.anchorObj`, `PSRUI` (affichage
--- de l'entrée de menu) et `pruneDeadStructures` (qui SUPPRIME) — et la règle du corpus est
--- explicite : *plus d'un consommateur ⇒ point unique, sinon les copies re-divergent*.
--- ⚠️ Si ces trois-là divergeaient, on obtiendrait le pire cas possible : un menu qui propose de
--- connecter une case que l'élagage juge ensuite non ancrable, donc une connexion posée puis
--- retirée toute seule — sans erreur, sans trace.
--- ⚖️ Critère volontairement ÉTROIT : mur ou sol RÉEL. Un objet décoratif ferait une ancre qu'un
--- joueur peut ramasser, et l'ancre partirait avec lui, en silence.
---@param o IsoObject
---@return boolean
function WorldUtil.isAnchorable(o)
    if not o then return false end
    if instanceof(o, "IsoThumpable") then return true end
    local spr = o.getSprite and o:getSprite()
    local pr  = spr and spr:getProperties()
    if not pr then return false end
    return pr:has("WallN") or pr:has("WallW") or pr:has("WallNW")
        or (IsoFlagType and pr:has(IsoFlagType.solidfloor))
end

---@param pb table PowerBankObject
---@return number nombre d'entrées élaguées
function WorldUtil.pruneDeadStructures(pb)
    local list = pb and pb.PSR_manualStructures
    if not list or #list == 0 then return 0 end
    local removed = 0
    for i = #list, 1, -1 do
        local a = list[i]
        local sq = a and getSquare(a.x, a.y, a.z)
        if sq then                       -- case chargée : on SAIT. Sinon on ne conclut rien.
            local stillTagged = false
            local objs = sq:getObjects()
            for j = 0, (objs and objs:size() or 0) - 1 do
                local o = objs:get(j)
                -- ⚠️ `hasModData()` AVANT `getModData()` : ce dernier ALLOUE une KahluaTable
                --    quand l'objet n'en a pas (bytecode 42.20.3). Seul changement conservé du
                --    2026-08-21 — c'est un gain réel et sans effet de bord.
                local md = o and o.hasModData and o:hasModData() and o:getModData() or nil
                local t  = md and md.PSR_structBank
                if t and t.x == pb.x and t.y == pb.y and t.z == pb.z then
                    stillTagged = true
                    break
                end
            end
            -- 🔴 TENTATIVE ANNULÉE LE 2026-08-21, ET IL FAUT GARDER POURQUOI.
            --    J'avais ajouté un 3ᵉ état « aucun objet ancrable ici ⇒ on ne sait pas, on ne
            --    touche à rien », au motif que le modData d'une ancre VANILLA pourrait ne pas
            --    survivre à un rechargement.
            --    ⚠️ Elle était fausse DEUX FOIS :
            --      · elle ne protégeait pas du risque invoqué — un mur de carte encore debout
            --        EST ancrable, donc l'élagage passait quand même ;
            --      · et elle cassait le cas pour lequel cette fonction existe : une structure
            --        réellement DÉMOLIE ne laisse plus rien d'ancrable ⇒ on n'élaguait plus, et
            --        la bank facturait une ruine indéfiniment.
            --    🔑 *Une garde qui ne couvre pas le risque qu'elle invoque et casse le cas nominal
            --    n'est pas une précaution : c'est une régression avec une bonne intention.*
            --    ⚖️ Le vrai risque se MESURE (`docs/TEST_1.75.md` `V-4`, ⓐ liste ⓑ menu). S'il se
            --    confirme, la réponse n'est pas ici : c'est de ne pas faire dépendre l'état du
            --    menu d'un modData de carte.
            if not stillTagged then
                table.remove(list, i)
                removed = removed + 1
            end
        end
    end
    if removed > 0 and pb.saveData then pb:saveData(true) end
    return removed
end

---Removes the link entry pointing to (x,y,z) from pb.PSR_linkedBanks.
---@param pb table PowerBankObject
---@param x number
---@param y number
---@param z number
function WorldUtil.removeLinkEntry(pb, x, y, z)
    local links = pb.PSR_linkedBanks
    if not links then return end
    for i = #links, 1, -1 do
        if links[i].x == x and links[i].y == y and links[i].z == z then
            table.remove(links, i)
        end
    end
end

---BFS through the full network. Returns total panels, direct-link info table,
---total charge, total drain and total CAPACITY. infos only contains direct neighbours of pb.
---
-- 🔴 2026-08-07 — `networkCapacity` ADDED (signal `Ozymandias NZ` : *« linked banks don't seem to
-- increase battery capacity for the network »*). His report was right about the SCREEN and wrong
-- about the mechanics : the server DOES pool capacity (`PowerBankSystem_Server:432-438` sums it,
-- clamps `newCharge` on it, then redistributes pro rata), but this function accumulated panels,
-- charge and drain — **and never capacity** — so no client surface could ever show the network
-- total. *Three of the four network aggregates existed ; the fourth was missing.*
-- ✅ `maxcapacity` is safe to read here : it is listed in `PBSystem.savedObjectModData` right next
-- to `charge`, `drain` and `npanels`, the three keys this loop already reads through `md[]`.
-- Verified before writing — an aggregate over an unsaved key would sum silently to zero and pass
-- every check we have.
-- ⚠️ Note the asymmetry that is DELIBERATE : charge and capacity are SUMMED, drain is a `math.max`.
-- That mirrors the server, where a single drain is billed per network (classified as balancing, not
-- a defect, on 2026-08-04). Do not "harmonise" it into a sum.
---@param pb table PowerBankObject (client-side Lua object)
---@return number, table, number, number, number
function WorldUtil.getLinkedBanksPanelInfo(pb)
    local infos = {}
    local networkTotal    = pb.npanels     or 0
    local networkCharge   = pb.charge      or 0
    local networkDrain    = pb.drain       or 0
    local networkCapacity = pb.maxcapacity or 0

    local visited = { [pb.x .. "," .. pb.y .. "," .. pb.z] = true }
    local queue   = {}

    for _, link in ipairs(pb.PSR_linkedBanks or {}) do
        local k = link.x .. "," .. link.y .. "," .. link.z
        if not visited[k] then
            visited[k] = true
            table.insert(queue, { link = link, direct = true })
        end
    end

    while #queue > 0 do
        local item = table.remove(queue, 1)
        local link = item.link
        local sq = getSquare(link.x, link.y, link.z)
        local npanels = 0
        if sq then
            local specials = sq:getSpecialObjects()
            for i = 0, specials:size() - 1 do
                local obj = specials:get(i)
                if instanceof(obj, "IsoGenerator") and WorldUtil.getType(obj) == "PowerBank" then
                    local md = obj:getModData()
                    npanels       = md["npanels"] or 0
                    networkCharge = networkCharge + (md["charge"] or 0)
                    networkDrain  = math.max(networkDrain, md["drain"] or 0)
                    networkCapacity = networkCapacity + (md["maxcapacity"] or 0)
                    for _, fl in ipairs(md["PSR_linkedBanks"] or {}) do
                        local k2 = fl.x .. "," .. fl.y .. "," .. fl.z
                        if not visited[k2] then
                            visited[k2] = true
                            table.insert(queue, { link = fl, direct = false })
                        end
                    end
                    break
                end
            end
        end
        networkTotal = networkTotal + npanels
        if item.direct then
            table.insert(infos, {
                x = link.x, y = link.y, z = link.z,
                dir = WorldUtil.getDirection(pb.x, pb.y, link.x, link.y),
                npanels = npanels,
            })
        end
    end

    return networkTotal, infos, networkCharge, networkDrain, networkCapacity
end

PSR.WorldUtil = WorldUtil
