--[[
    "psr_powerbank" server system — B42 rewrite (SGlobalObjects API)
--]]

-- Bail out on a pure client. The GUARD IS CORRECT — its old justification was not, and
-- was corrected on 2026-08-19. It read "coop host = isClient AND isServer both true",
-- which our own MP table REFUTED on 2026-08-16 : a coop host runs a SEPARATE server
-- process, and the two worlds are strictly disjoint, so isClient() and isServer() are
-- NEVER true together (measured in both processes).
-- What actually happens, and it is simpler than the old story : in the coop host's
-- server process isClient() is already false, so this line does not fire there and the
-- server system stays alive. The only process it turns away is a real client
-- (dedicated client, or the coop host's CLIENT process), which is what we want.
-- Do not "fix" the condition — only the reasoning behind it was wrong.
if isClient() and not isServer() then return end

local PSR = require "PSR/Utilities"
local Powerbank = require "PSR/PowerBank/PowerBankObject_Server"

---@class PowerbankSystem_Server : PowerbankSystem
---@field instance PowerbankSystem_Server
local PBSystem = require("PSR/PowerBankSystem_Shared"):new({})
PBSystem.__index = PBSystem

-- 🔌 `PSR_coverRect` (v1.71) — LE RECTANGLE DE COUVERTURE QU'ON A RÉELLEMENT APPLIQUÉ.
--    Il DOIT être dans cette liste blanche : `addGeneratorPos` écrit dans le CHUNK, donc dans la
--    sauvegarde, alors que l'état de la bank vit dans son modData. Si le rectangle ne persistait
--    pas, une bank éteinte après un rechargement ne saurait plus quoi retirer — et le reliquat
--    deviendrait définitif. *Ce qu'on doit défaire et ce qui déclenche le geste doivent survivre
--    au même événement.* → `psrSweepRect` / `psrCoverRect`, `docs/ROADMAP.md` (chantier du 14/08).
-- ⚠️ `PSR_coverTries` (2026-08-16) DOIT être persisté : le plafond de tentatives ne vaut rien s'il
--    repart à zéro à chaque rechargement — c'est précisément ce qui rendait le retry éternel sur un
--    serveur dédié, où le rectangle, lui, survivait au redémarrage.
PBSystem.savedObjectModData = { 'on', 'activated', 'batteries', 'charge', 'maxcapacity', 'drain', 'npanels', 'panels', "lastHour", "conGenerator", "PSR_linkedBanks", "PSR_computer", "PSR_manualStructures", "PSR_coverRect", "PSR_coverLegacyCleaned", "PSR_coverTries" }

function PBSystem:initSystem()
    PSR.PBSystem_Server = self
    self.system:setObjectModDataKeys(self.savedObjectModData)
    self.updateEveryTenMinutes = ((SandboxVars.PSR and SandboxVars.PSR.ChargeFreq) or 1) == 1
    if self.updateEveryTenMinutes then
        Events.EveryTenMinutes.Add(PBSystem.updatePowerbanks)
    else
        Events.EveryHours.Add(PBSystem.updatePowerbanks)
    end
    Events.EveryDays.Add(PBSystem.EveryDays)
    -- 42.19 : suppress the transient indoor "toxic gas" warning every game minute (see suppressToxic).
    Events.EveryOneMinute.Add(PBSystem.suppressToxic)
end

function PBSystem:noise(message)
    if self.wantNoise then print("PSR_Server: " .. message) end
end

function PBSystem:getInitialStateForClient()
    return nil
end

function PBSystem:OnChunkLoaded(wx, wy)
    local globalObjects = self.system:getObjectsInChunk(wx, wy)
    for i = 1, globalObjects:size() do
        local globalObject = globalObjects:get(i - 1)
        local square = getCell():getGridSquare(globalObject:getX(), globalObject:getY(), globalObject:getZ())
        local isoObject = self:getIsoObjectOnSquare(square)
        if isoObject then
            self:loadIsoObject(isoObject)
        elseif square then
            -- 🩹 PREUVE POSITIVE EXIGEE (audit 2026-08-04).
            -- `getIsoObjectOnSquare` rend nil dans DEUX cas qui n'ont rien a voir :
            --   · la case est chargee et ne porte aucune bank  -> la bank a bien disparu ✅
            --   · `square` est nil (chunk pas encore charge)   -> ON NE SAIT PAS ❌
            -- La fonction commence par `if not square then return end`, donc les deux cas
            -- arrivaient ici et l'entree etait supprimee dans les deux. Un nettoyage destructif
            -- ne doit jamais agir sur une absence d'information (regle payee sur PFR : faux
            -- degel = perte de nourriture definitive).
            -- ⚠️ Cette structure vient du vanilla (`SGlobalObjectSystem.lua`), ou la perte est
            -- triviale (un feu de camp). Ici elle coutait l'etat complet d'une bank. Le vanilla
            -- `MOCampfire` fait d'ailleurs ce qui manquait : relire le modData avant de decider.
            self:noise('OnChunkLoaded: luaObject without isoObject, removing')
            self.system:removeObject(globalObject)
        end
    end
    self.system:finishedWithList(globalObjects)
end

---Wrap a global object's mod data with PowerBank methods. Safe to call multiple times.
---@param globalObject table
---@return PowerBankObject_Server
function PBSystem:wrapGlobalObject(globalObject)
    -- 🛡️ FILET v1.70 — ce `nil` a coûté une exception PAR TICK chez des joueurs en 1.69.
    -- `getObjectByIndex` rend `null` hors plage (mesuré par la pile de `The Real Slark Shady`,
    -- comportement NON documenté côté JavaDoc), et on déréférençait sans regarder. La CAUSE est
    -- corrigée à sa source (convention d'index, `PowerBankSystem_Client:psrBankByIndex`) ; ce
    -- garde-fou existe pour que le même écart ne puisse plus jamais **inonder la console**.
    -- 🔑 Il rend `nil`, il n'avale pas : les appelants sains bouclent déjà dans les bornes, donc
    --    une seule trace suffit à dire qu'un appelant est fautif — sans quoi le correctif serait
    --    muet, donc indiscernable d'un correctif absent.
    if not globalObject then
        if not self.psrWarnedNilGlobal then
            self.psrWarnedNilGlobal = true
            self:noise('wrapGlobalObject called with nil (caller used an out-of-range index)')
        end
        return nil
    end
    local pb = globalObject:getModData()
    if getmetatable(pb) ~= Powerbank then
        pb.x = globalObject:getX()
        pb.y = globalObject:getY()
        pb.z = globalObject:getZ()
        pb.luaSystem = self
        setmetatable(pb, Powerbank)
    end
    return pb
end

---@param x number
---@param y number
---@param z number
---@return PowerBankObject_Server?
function PBSystem:getLuaObjectAt(x, y, z)
    local go = self.system:getObjectAt(x, y, z)
    if go then return self:wrapGlobalObject(go) end
end

---@param square IsoGridSquare
---@return PowerBankObject_Server?
function PBSystem:getLuaObjectOnSquare(square)
    if not square then return end
    return self:getLuaObjectAt(square:getX(), square:getY(), square:getZ())
end

---@param i number  (0-indexed)
---@return PowerBankObject_Server
function PBSystem:getLuaObjectByIndex(i)
    return self:wrapGlobalObject(self.system:getObjectByIndex(i))
end

---@return number
function PBSystem:getLuaObjectCount()
    return self.system:getObjectCount()
end


---Create or load the global object entry for an IsoObject.
---@param isoObject IsoObject
function PBSystem:loadIsoObject(isoObject)
    local isoMd = isoObject:getModData()
    local x, y, z = isoObject:getX(), isoObject:getY(), isoObject:getZ()

    local go = self.system:getObjectAt(x, y, z)
    local pb
    if go then
        pb = self:wrapGlobalObject(go)
        if pb.on ~= nil then
            pb:stateToIsoObject(isoObject)
        else
            pb:stateFromIsoObject(isoObject)
        end
    else
        go = self.system:newObject(x, y, z)
        pb = self:wrapGlobalObject(go)
        pb:stateFromIsoObject(isoObject)
    end
end

---@param luaPb PowerBankObject_Server
function PBSystem:removeLuaObject(luaPb)
    local go = self.system:getObjectAt(luaPb.x, luaPb.y, luaPb.z)
    if go then self.system:removeObject(go) end
end

---triggered by SGlobalObjectSystem when an IsoObject is placed/loaded
---@param isoObject IsoObject
function PBSystem:OnObjectAdded(isoObject)
    local PSRType = PSR.WorldUtil.getType(isoObject)
    if not PSRType then
        return
    elseif PSRType == "PowerBank" then
        if not instanceof(isoObject, "IsoGenerator") then
            isoObject = PSR.WorldUtil.replaceIsoObjectWithGenerator(isoObject)
        end
        if self:isValidIsoObject(isoObject) then
            self:loadIsoObject(isoObject)
        end
    elseif PSRType == "Panel" then
        local modData = isoObject:getModData()
        modData.pbLinked = nil
        modData.connectDelta = nil
        isoObject:transmitModData()
    end
end


---triggered by SGlobalObjectSystem when an IsoObject is about to be removed
---@param isoObject IsoObject
function PBSystem:OnObjectAboutToBeRemoved(isoObject)
    local PSRType = PSR.WorldUtil.getType(isoObject)
    -- Nettoyage si un Desktop Computer lié au PSR est ramassé (IsoMoveable vanilla, pas un PSRType)
    local linkedBank = isoObject:getModData().PSR_linkedBank
    if linkedBank then
        local pb = self:getLuaObjectAt(linkedBank.x, linkedBank.y, linkedBank.z)
        if pb then
            pb.PSR_computer = nil
            pb:saveData(true)
        end
        isoObject:getModData().PSR_linkedBank = nil
        isoObject:transmitModData()
    end
    if not PSRType then
        return
    end
    if self:isValidIsoObject(isoObject) then
        local luaObject = self:getLuaObjectOnSquare(isoObject:getSquare())
        if not luaObject then return end
        for _, link in ipairs(luaObject.PSR_linkedBanks or {}) do
            local linked = self:getLuaObjectAt(link.x, link.y, link.z)
            if linked then
                PSR.WorldUtil.removeLinkEntry(linked, luaObject.x, luaObject.y, luaObject.z)
                linked:saveData(true)
            end
        end
        -- Clear OUTGOING links so nothing keeps pointing at a bank that no longer exists
        -- (player-observed 2026-07-04: computer + panels still linked after the bank was removed).
        -- Computer: clear the linked computer's back-reference (mirrors UnlinkComputer).
        if luaObject.PSR_computer then
            local csq = getSquare(luaObject.PSR_computer.x, luaObject.PSR_computer.y, luaObject.PSR_computer.z)
            if csq then
                local cobjs = csq:getObjects()
                for i = 0, cobjs:size() - 1 do
                    local obj = cobjs:get(i)
                    local lb = obj and obj:getModData().PSR_linkedBank
                    if lb and lb.x == luaObject.x and lb.y == luaObject.y and lb.z == luaObject.z then
                        obj:getModData().PSR_linkedBank = nil
                        obj:transmitModData()
                        break
                    end
                end
            end
        end
        -- Panels: clear each connected panel's pbLinked/connectDelta (mirrors disconnectPanel).
        for _, panel in ipairs(luaObject.panels or {}) do
            local psq = getSquare(panel.x, panel.y, panel.z)
            if psq then
                local pobjs = psq:getSpecialObjects()
                for i = 0, pobjs:size() - 1 do
                    local obj = pobjs:get(i)
                    local md = obj and obj:getModData()
                    -- Only clear panels actually linked to THIS bank (coord check, like the computer
                    -- block above) so a stale/foreign panel linked to another bank is left untouched.
                    if md and md.pbLinked and md.pbLinked.x == luaObject.x
                       and md.pbLinked.y == luaObject.y and md.pbLinked.z == luaObject.z then
                        md.pbLinked = nil
                        md.connectDelta = nil
                        obj:transmitModData()
                        break
                    end
                end
            end
        end
        -- Clear the back-ref tag on each manually-connected extension's anchor square (mirrors the
        -- computer/panel cleanup): the bank's own PSR_manualStructures list dies with the bank object,
        -- but the anchor square's PSR_structBank tag would otherwise stay stale.
        for _, s in ipairs(luaObject.PSR_manualStructures or {}) do
            for _, c in ipairs(PSR.Structures.resolveSquares(s.x, s.y, s.z)) do
                local ssq = getSquare(c.x, c.y, c.z)
                if ssq then
                    local sobjs = ssq:getObjects()
                    if sobjs then
                        for i = 0, sobjs:size() - 1 do
                            local obj = sobjs:get(i)
                            local md = obj and obj:getModData()
                            if md and md.PSR_structBank and md.PSR_structBank.x == luaObject.x
                               and md.PSR_structBank.y == luaObject.y and md.PSR_structBank.z == luaObject.z then
                                md.PSR_structBank = nil
                                obj:transmitModData()
                                break
                            end
                        end
                    end
                end
            end
        end
        -- Clear the injected electricity BEFORE the object goes away (picked up / destroyed while
        -- still on) so appliances don't keep power for free. Must run before removeLuaObject while
        -- the square + generator are still resolvable.
        luaObject:removePowerCoverage()
        self:removeLuaObject(luaObject)
    elseif PSRType == "Panel" then
        self:removePanel(isoObject)
    end
end

function PBSystem:OnClientCommand(command, playerObj, args)
    local fn = self.Commands[command]
    if fn ~= nil then fn(playerObj, args) end
end

function PBSystem:removePanel(panel)
    local pbData = panel:getModData().pbLinked
    if pbData == nil then return end
    local pb = self:getLuaObjectAt(pbData.x, pbData.y, pbData.z)
    panel:getModData().pbLinked = nil
    panel:transmitModData()
    if pb == nil then return end
    local x, y, z = panel:getX(), panel:getY(), panel:getZ()
    for i = #pb.panels, 1, -1 do
        local _panel = pb.panels[i]
        if _panel.x == x and _panel.y == y and _panel.z == z then
            table.remove(pb.panels, i)
            pb.npanels = (pb.npanels or 1) - 1
            break
        end
    end
    pb:saveData(true)
end

do
    local o = PSR.delayedProcess:new{maxTimes=999}

    function o.process(tick)
        if not o.data then o:stop() return end
        for i = #o.data, 1, -1 do
            if o.data[i].obj:getObjectIndex() == -1 then
                local square = o.data[i].sq
                local generator = square and square:getGenerator()
                if generator then
                    generator:setActivated(false)
                    generator:remove()
                end
                table.remove(o.data, i)
            end
        end
        if o.data[1] == nil or o.times <= 1 then o:stop() return end
        o.times = o.times - 1
    end

    function o:addItem(isoObject)
        if not self.data then
            self.data = {}
            self.event.Add(self.process)
        end
        self.times = self.maxTimes
        table.insert(self.data, { obj = isoObject, sq = isoObject:getSquare() })
    end

    PBSystem.processRemoveObj = o
end

---@param character IsoPlayer
---@param generator IsoGenerator
function PBSystem:onPlugGenerator(character, generator)
    if not (character and generator and generator:getSquare()) then return end
    local area = PSR.WorldUtil.getValidBackupArea(character:getPerkLevel(Perks.Electricity))
    local luaPowerbanks = PSR.WorldUtil.getPowerBanksInArea(generator:getSquare(), area.radius, area.levels, area.distance)
    if luaPowerbanks[1] == nil then return end
    local x, y, z = generator:getX(), generator:getY(), generator:getZ()
    for i = 1, #luaPowerbanks do
        local pb = luaPowerbanks[i]
        local connect = true
        if pb.conGenerator and IsoUtils.DistanceToSquared(pb.x, pb.y, pb.z, pb.conGenerator.x, pb.conGenerator.y, pb.conGenerator.z)
                                <= IsoUtils.DistanceToSquared(pb.x, pb.y, pb.z, x, y, z) then
            connect = false
        end
        if connect then pb:connectBackupGenerator(generator) end
    end
end

---@param character IsoPlayer
---@param generator IsoGenerator
function PBSystem:onUnPlugGenerator(character, generator)
    if not generator then return end
    local x, y, z = generator:getX(), generator:getY(), generator:getZ()
    for i = 0, self.system:getObjectCount() - 1 do
        local pb = self:getLuaObjectByIndex(i)
        -- 🛡️ `pb` peut être nil depuis la v1.70 (filet de `wrapGlobalObject`) — 1 des 4 sites
        --    consommateurs qui déréférençaient le résultat sans le vérifier : le filet rendait
        --    `nil` proprement et on plantait une ligne plus bas. *Un filet dont les appelants ne
        --    lisent pas le retour ne fait que déplacer l'exception.*
        if pb and pb.conGenerator and pb.conGenerator.x == x and pb.conGenerator.y == y and pb.conGenerator.z == z then
            pb:disconnectBackupGenerator(generator)
        end
    end
end

---@param character IsoPlayer
---@param generator IsoGenerator
---@param activate boolean
function PBSystem:onActivateGenerator(character, generator, activate)
    if not generator then return end
    local x, y, z = generator:getX(), generator:getY(), generator:getZ()
    for i = 0, self.system:getObjectCount() - 1 do
        local pb = self:getLuaObjectByIndex(i)
        if pb and pb.conGenerator and pb.conGenerator.x == x and pb.conGenerator.y == y and pb.conGenerator.z == z then
            pb.conGenerator.ison = activate
        end
    end
end

function PBSystem:onTransferItem(action, character, item, srcContainer, destContainer, dropSquare)
    local maxCapacity = item:getModData().PSR_maxCapacity
    if not maxCapacity then return end
    local src = srcContainer:getParent()
    local dst = destContainer:getParent()
    local remove = src ~= nil and PSR.WorldUtil.objectIsType(src, "PowerBank")
    local add    = dst ~= nil and PSR.WorldUtil.objectIsType(dst, "PowerBank")
    if not (remove or add) then return end
    local capacity = maxCapacity * (1 - math.pow((1 - (item:getCondition() / 100)), 6))
    local charge = capacity * item:getCurrentUsesFloat()
    if remove then
        local pb = self:getLuaObjectAt(src:getX(), src:getY(), src:getZ())
        if not pb then return end
        pb.batteries = (pb.batteries or 0) - 1
        if pb.batteries > 0 then
            pb.charge = (pb.charge or 0) - charge
            pb.maxcapacity = (pb.maxcapacity or 0) - capacity
        else
            pb.charge = 0
            pb.maxcapacity = 0
        end
        pb:updateGenerator()
        pb:updateSprite()
        pb:saveData(true)
    end
    if add then
        local pb = self:getLuaObjectAt(dst:getX(), dst:getY(), dst:getZ())
        if not pb then return end
        pb.batteries = pb.batteries + 1
        pb.charge = pb.charge + charge
        pb.maxcapacity = pb.maxcapacity + capacity
        pb:updateGenerator()
        pb:updateSprite()
        pb:saveData(true)
    end
end

function PBSystem.EveryDays()
    local self = PBSystem.instance
    for i = 0, self.system:getObjectCount() - 1 do
        local pb = self:getLuaObjectByIndex(i)
        local isopb = pb and pb:getIsoObject() or nil
        if isopb then
            local inv = isopb:getContainer()
            pb:degradeBatteries(inv)
            pb:calculateBatteryStats(inv)
        end
        pb:checkPanels()
    end
end

--------------------------------------------------------------------------------
-- ⚡ « PAS DE BANK QUI FOURNIT = PAS DE COURANT PSR » — prédicat unique (2026-08-13)
--------------------------------------------------------------------------------
-- Décision Commandeur du jour, verrouillée dans `docs/DECISIONS.md` :
--   *« pas de bank allumée = pas d'électricité »*, étendu à *« éteinte / démontée /
--     vidée de ses batteries ⇒ elle ne peut plus fournir »*.
--
-- 🔑 LES TROIS PORTES TOMBENT SUR UN SEUL PRÉDICAT, et aucune n'a demandé de code neuf :
--    · éteinte              -> `activated` (déjà lu par `recordToxicDebt`)
--    · vidée de batteries   -> `maxcapacity` == 0 (alimenté par `PSR_maxCapacity`,
--                              cf. `shared/PSR/Items/PSR_recipecode.lua:114`)
--    · démontée / disparue  -> `getIsoObject()` == nil
--    ⚖️ On ne compte donc JAMAIS les batteries à la main : on lit la grandeur que le
--       système tient déjà à jour, celle-là même qui produit `X/Y kWh` dans le log réseau.
--
-- ⚠️ LECTURE PURE, aucun effet de bord. Ces deux fonctions n'ont volontairement aucun
--    site d'appel à leur écriture : elles sont la fondation du lot électrique, posée
--    seule pour qu'elle ne puisse rien casser. Le câblage vient ensuite.
--
-- 📌 Symétrie à ne pas oublier au câblage : le vrai sujet n'est pas d'empêcher
--    d'ALLUMER (le terminal), c'est d'ÉTEINDRE ce qui l'est déjà — c'est le symptôme
--    observé (lampes allumées après démontage de la bank). Une garde qui ne ferait que
--    griser des boutons laisserait le défaut entier.

--- Cette bank peut-elle fournir du courant ?
---@param pb table|nil objet bank (membre de réseau)
---@return boolean
function PBSystem:bankSupplies(pb)
    if not pb then return false end
    if not pb.activated then return false end               -- éteinte
    if (pb.maxcapacity or 0) <= 0 then return false end     -- plus aucune batterie
    if not pb:getIsoObject() then return false end          -- démontée / disparue
    return true
end

--- Au moins une bank du réseau de `pb` fournit-elle du courant ?
--- ⚠️ C'est bien le RÉSEAU qui décide, jamais la bank seule : le terminal pilote des
---    appareils alimentés par l'ensemble, et une bank vide voisine d'une bank pleine
---    ne doit rien couper.
---@param pb table|nil
---@return boolean
function PBSystem:networkSupplies(pb)
    if not pb then return false end
    local network = self.getNetwork and self:getNetwork(pb) or nil
    if not network then return self:bankSupplies(pb) end     -- repli : la bank seule
    for _, member in ipairs(network) do
        if self:bankSupplies(member) then return true end
    end
    return false
end

--- Éteint les appareils d'un réseau qui vient de cesser de fournir.
--- 🔑 C'est LE correctif du symptôme observé le 13/08 : *« j'ai démonté la bank, les lampes
---    que j'ai fixées au mur sont toujours allumées »*. Couper l'alimentation ne suffit pas —
---    **un appareil déjà allumé garde son état tant que rien ne le relit.**
--- 🛑 GARDE-FOU (décision Commandeur, `docs/DECISIONS.md` 13/08) : on n'éteint PAS un appareil
---    alimenté par la GRILLE PUBLIQUE. En début de partie elle tourne encore, et sans cette
---    garde PSR irait éteindre des appareils qu'il n'alimente pas, chez une population énorme
---    de saves. ⚖️ Le coût d'erreur n'est pas symétrique : couper est réversible, éteindre le
---    frigo de quelqu'un lui détruit sa nourriture.
--- ⚠️ NON COUVERT ET DIT COMME TEL : un appareil alimenté par un GÉNÉRATEUR À ESSENCE tiers.
---    `checkObjectPowered()` / `haveElectricity()` répondent « alimenté » y compris quand c'est
---    NOUS qui alimentions — ils ne discriminent pas la source. Seul `hasGridPower()` désigne
---    une source précise. Ce cas demande une mesure avant d'être traité : ne pas l'improviser.

-- 🔴🔴 RÉGRESSION v1.68 CORRIGÉE EN v1.70 — DEUX SIGNALANTS, NOURRITURE PERDUE.
--    `clockwork` : *« my freezer and fridge turn into bookshelfs with name Freezer (off) […]
--    they wont freeze again »* · `Zadesh` : *« my chest freezer is now KIA, RIP lamb chops »*.
--    Reproduit en SOLO par le Commandeur le 2026-08-13.
--
-- 🔑 LA DISTINCTION QUE JE N'AVAIS PAS FAITE : « éteindre » n'a pas le même prix selon l'appareil.
--    · lampe, TV, radio, four, lave-linge → `setActivated(false)` : état VOLATILE, un clic le défait.
--    · frigo / congélateur → `container:setType("freezer_off")` : état **PERSISTÉ DANS LA SAVE**
--      (bytecode 42.20 — `ItemContainer.save()` sérialise `this.type` en premier champ).
--    · Cold Unit PFR → `modData.PFR_on = false` : persisté aussi, et PFR fait CHAUFFER la pièce
--      tant qu'elle est à `false` (`PFRRoomScan` : *« cooling while ON + powered, warming otherwise »*).
--    Il n'existe AUCUN rallumage automatique — vérifié par grep exhaustif des sites d'appel :
--    `controlDevice(..., false)` est émis ici, et `on=true` ne vient QUE du clic joueur sur le
--    Solar Computer. ⇒ **la coupure était un aller SANS RETOUR sur un état gravé dans la save.**
--
-- ⚖️ ET LE GAIN ÉTAIT NUL. 📚 Doc lue (`zombie.inventory.ItemContainer.getTemprature`, bytecode
--    42.20) : `if (isPowered() && (isFridge() || isFreezer())) return 0.2f`. **Le moteur gate déjà
--    le froid sur l'alimentation** ; PFR gate le sien de même (`isObjPowered`). Un frigo privé de
--    courant ne refroidissait donc plus AVANT qu'on y touche. On gravait un état destructeur et
--    définitif pour n'obtenir strictement rien.
-- 🔑 *La question à se poser devant toute extinction automatique n'est pas « est-ce cohérent ? »
--    mais « qui la DÉFAIT, et à quel prix si personne ne la défait ? »* — un effet réversible et
--    un effet gravé ne se traitent pas dans la même boucle, même quand ils s'écrivent pareil.
-- ⚖️ La bascule reste entière côté Solar Computer : là c'est le joueur qui la demande et qui peut
--    la défaire. Ce qui est retiré, c'est le déclenchement AUTOMATIQUE, que personne ne défait.
-- 🧊 Déplacée dans `shared/PSR/Utilities.lua` le 2026-08-16 — POINT UNIQUE (voir son en-tête).
-- Le panneau client portait sa propre copie (`coolingType`), plus courte d'un type (`coldunit`).
-- ⚠️ Lue depuis `PSR`, que ce fichier `require` nommément en tête — donc peuplée ici avec
--    certitude. La poser sur `PSR.WorldUtil` aurait été une capture au chargement du module, le
--    défaut exact déjà payé sur `SandboxVars.PSR` (cf. `PowerBankSystem_Shared.lua`).
-- L'alias local est conservé pour ne pas toucher les 3 sites d'appel existants.
local PSR_PERSISTENT_OFF = PSR.PERSISTENT_OFF

--------------------------------------------------------------------------------
-- 🛑 COUPE AUTOMATIQUE SUSPENDUE — arbitrage Commandeur, 2026-08-14
--------------------------------------------------------------------------------
-- La règle *« tant qu'aucune bank ne fournit, rien ne doit être allumé »* (v1.68) a produit
-- **quatre régressions distinctes en 24 h**, toutes de la même forme : `bankSupplies` rend
-- `false` sur une **absence d'information**, et la coupe traite ce `false` comme une preuve.
--
--   · `Beerman`  — une 2ᵉ bank posée mais NON LIÉE est un réseau d'un seul membre, donc « ne
--     fournit pas » ; or `deviceList` est bâti **par BÂTIMENT**. ⇒ ***la coupe se décide par
--     RÉSEAU et s'applique par BÂTIMENT*** : sa bank morte à 3 tuiles éteignait toute la base
--     alimentée par l'autre. Il l'a prouvé lui-même en la retirant.
--   · `NickLouis` (+ son ami, coop) — tout s'éteint **pendant leur absence**, tout remarche à
--     leur retour : `bankSupplies` fait `if not pb:getIsoObject() then return false end`, et
--     `getIsoObject` → `getSquare()` → **nil quand le chunk n'est pas chargé**.
--     ⇒ *bank absente ≠ bank éteinte.*
--   · `Lellyna` / `Heckerpecker` — générateur à essence : le garde-fou « source étrangère »
--     existe ici et **pas** dans `PSRComputerPanel:applyControl`, qui refusait donc de RALLUMER.
--   · `clockwork` / `Zadesh` — le froid gravé dans la save (corrigé par `PSR_PERSISTENT_OFF`).
--
-- 🔑 La leçon était déjà écrite **dans ce fichier**, ~380 lignes plus haut (`OnChunkLoaded`) :
--    *« square est nil (chunk pas chargé) → ON NE SAIT PAS ❌ — un nettoyage destructif ne doit
--    jamais agir sur une absence d'information »*. Elle n'a pas été portée à `bankSupplies`.
--    *Corriger un cas, c'est balayer sa famille — le jumeau ne fait pas mal ENCORE.*
--
-- ⚖️ POURQUOI SUSPENDRE PLUTÔT QUE COLMATER (le gain a été mesuré, pas supposé) :
--    · pour le FROID, le gain est **nul** — 📚 bytecode 42.20, `ItemContainer.getTemprature()` :
--      `if (isPowered() && (isFridge() || isFreezer())) return 0.2f` ⇒ le moteur coupe déjà ;
--    · pour lampes/TV/radios, le gain est **cosmétique** (le vanilla ne les éteint pas non plus).
--    Coût constaté en face : nourriture perdue, base éteinte à distance, terminal verrouillé.
--    ⇒ *Avant d'automatiser un geste : que se passe-t-il si je ne le fais PAS ? « Rien de
--    différent » ⇒ c'est du risque pur.* On revient au comportement d'avant la v1.68, éprouvé
--    et jamais signalé.
--
-- ⛔ NE PAS repasser ce drapeau à `true` sans avoir traité les QUATRE points ci-dessus **et**
--    exercé la coupe en jeu (solo · hôte coop · client de dédié). La fonction est conservée
--    entière exprès : elle reviendra corrigée, pas réécrite de mémoire.
-- 🔒 Point de lecture UNIQUE — la coupe a **deux** portes (la passe réseau `updateNetwork` et
--    l'extinction immédiate dans `PowerBankObject_Server:activate`). N'en garder qu'une seule
--    serait précisément l'erreur qu'on vient de payer.
local PSR_AUTOCUT_ENABLED = false

--- Lecture inter-fichiers du drapeau ci-dessus (`PowerBankObject_Server` en a besoin).
---@return boolean
function PBSystem:autoCutEnabled()
    return PSR_AUTOCUT_ENABLED
end

---@param announce boolean|nil journaliser ? (vrai au 1er passage seulement — voir l'appelant)
function PBSystem:cutNetworkDevices(network, announce)
    -- 🔬 2026-08-13 — COMPTEURS SÉPARÉS, parce que le premier run n'a RIEN journalisé et que
    --    `n == 0` avait DEUX causes indiscernables : aucun appareil actif, ou tous sautés par
    --    le garde-fou `hasGridPower`. Un seul chiffre ne pouvait pas les départager.
    -- 🔑 On compte donc les trois grandeurs séparément et on les imprime TOUJOURS au 1er passage,
    --    même à zéro : *un zéro qui ne s'imprime pas est indiscernable d'un code qui ne tourne pas.*
    -- `spared` = appareils dont l'extinction serait PERSISTÉE et que personne ne défait (v1.70).
    -- Compté à part et non fondu dans `skipped` : les deux abstentions n'ont pas la même raison,
    -- et un jour où ce chiffre remontera anormalement, il faut savoir LAQUELLE a joué.
    local n, skipped, seen, spared = 0, 0, 0, 0
    -- Accumulateurs de la sonde « garde-fou » — portée FONCTION, pas boucle : la ligne de
    -- journal est imprimée après les membres, elle doit voir leurs totaux.
    for _, member in ipairs(network) do
        -- 🔴 CAUSE TROUVÉE LE 13/08 (2e test du Commandeur : *« le four ne s'éteint pas si je le
        --    rallume manuellement »*, et AUCUNE trace journalisée) : `deviceList` était PÉRIMÉ.
        --    Mon bloc tournait en TÊTE de `updateNetwork`, donc AVANT la boucle qui appelle
        --    `member:updateDrain()` — et `updateDrain` est justement ce qui reconstruit la liste
        --    et recalcule `dev.active`. Pire : `shouldDrain()` peut être faux quand la bank est
        --    éteinte, donc la liste n'était PLUS JAMAIS rafraîchie dans l'état où j'en ai besoin.
        -- 🔑 *Un instrument qui lit une donnée que personne ne met plus à jour mesure le passé.*
        -- ⇒ on force la reconstruction ici, pour lire l'état RÉEL et non celui d'avant l'extinction.
        if member.updateDrain then member:updateDrain() end

        -- 🔎 Générateurs ÉTRANGERS autour de cette bank, listés UNE FOIS par membre.
        -- 📏 Coût borné, et volontairement : `IsoCell` n'expose aucune itération globale
        --    ([[feedback-pz-b42-cell-iteration]]), donc on balaie un rayon — mais **une seule
        --    fois par bank**, pas par appareil, et **uniquement** quand le réseau ne fournit
        --    plus, un état anormal et bref. Rayon 20 = la portée native d'un générateur.
        -- 🔑 « Étranger » = `IsoGenerator` **activé** SANS `modData.generatorFullType`.
        --    Ce marqueur est posé sur toutes nos banks et sert déjà exactement à cette
        --    question côté client (`PowerBankSystem_Client:679`). On ne l'invente pas.
        -- 🔬 SONDE 2026-08-13 : le garde-fou n'a pas mordu (`0 skipped` avec un générateur à
        --    essence allumé). Deux causes restaient indiscernables — le balayage ne TROUVE pas le
        --    générateur, ou il le trouve et `isPoweringSquare` répond faux. On compte les deux.
        local foreign = {}
        local bsq = member.getSquare and member:getSquare() or nil
        if bsq then
            local bx, by, bz = bsq:getX(), bsq:getY(), bsq:getZ()
            -- 🔴 LIGNE RESTAURÉE le 2026-08-13 : mon script de nettoyage l'avait AVALÉE.
            --    La regex qui supprimait la sonde `lastWindow` portait un groupe optionnel
            --    `(?: *[^\n]*\n)?` destiné à sa 2ᵉ ligne — il a consommé la ligne SUIVANTE,
            --    c'est-à-dire l'ouverture de cette boucle. `gx` devenait indéfini.
            -- 🔑 Même famille que « PS 5.1 : une transformation qui échoue écrit du vide » :
            --    une substitution trop gourmande ne signale rien, elle emporte du code voisin.
            --    ⚙️ Ce qui l'a attrapée : le contrôle d'équilibre `ouvertures/end` (172 vs 173).
            --    Sans lui, un fichier syntaxiquement mort partait au Workshop.
            for gx = bx - 20, bx + 20 do
                for gy = by - 20, by + 20 do
                    local gsq = getSquare(gx, gy, bz)
                    if gsq then
                        local gobjs = gsq:getObjects()
                        for gi = 0, (gobjs and gobjs:size() or 0) - 1 do
                            local go = gobjs:get(gi)
                            if go and instanceof(go, "IsoGenerator") then
                                -- 🔴 PRÉDICAT CORRIGÉ le 2026-08-13, APRÈS MESURE. La version
                                --    précédente testait la PRÉSENCE de `generatorFullType` et
                                --    classait donc « à nous » TOUT générateur — le garde-fou ne
                                --    pouvait jamais mordre. Preuve : le Commandeur n'a qu'UNE
                                --    bank, la sonde annonçait « 2 vus dont 2 à nous ».
                                -- 🔑 `generatorFullType` est un champ **VANILLA** : le jeu le pose
                                --    sur tout `IsoGenerator` pour mémoriser l'item d'origine. PSR
                                --    ne fait que le renseigner comme le vanilla. ⇒ **le
                                --    discriminant est la VALEUR, jamais la présence.**
                                -- ⚠️ Ma faute d'origine : j'ai déduit la sémantique d'un
                                --    COMMENTAIRE côté lecteur (`PowerBankSystem_Client:679`) au
                                --    lieu de remonter à qui ÉCRIT le champ et avec quelle valeur.
                                --    Le commentaire décrivait un usage local, pas le sens du champ.
                                local gmd  = go.getModData and go:getModData() or nil
                                local gft  = gmd and gmd.generatorFullType or nil
                                local ours = false
                                if gft then
                                    if gft == "PSR.PowerBank" then
                                        ours = true
                                    else
                                        for _, psrFull in pairs(PSR.WorldUtil.PSRFullTypes or {}) do
                                            if gft == psrFull then ours = true end
                                        end
                                    end
                                end
                                if not ours and go.isActivated and go:isActivated() then
                                    foreign[#foreign + 1] = { x = gx, y = gy, z = bz }
                                end
                            end
                        end
                    end
                end
            end
        end

        for _, dev in ipairs(member.deviceList or {}) do
            seen = seen + 1
            -- 🛑 v1.70 — jamais d'extinction AUTOMATIQUE sur un appareil dont l'état off est gravé
            --    dans la save et que rien ne relève. Voir le bloc `PSR_PERSISTENT_OFF` ci-dessus.
            if dev.active and PSR_PERSISTENT_OFF[dev.dtype] then
                spared = spared + 1
            elseif dev.active then
                local skip = false
                local sq = getSquare(dev.x, dev.y, dev.z)
                if sq then
                    local objs = sq:getObjects()
                    for i = 0, (objs and objs:size() or 0) - 1 do
                        local o = objs:get(i)
                        if o and o.hasGridPower and o:hasGridPower() then skip = true end
                    end
                end
                -- 🛑 GARDE-FOU « AUTRE SOURCE », 2e moitié (2026-08-13) — le générateur TIERS.
                -- 🔑 Le prédicat manquait parce que je n'avais pas le moyen de distinguer un
                --    générateur à essence d'une de nos banks : les deux sont des `IsoGenerator`,
                --    et `checkObjectPowered()` répond « alimenté » sans dire PAR QUI.
                --    Deux lectures l'ont débloqué, et aucune n'est une supposition :
                --      · `modData.generatorFullType` marque NOS banks (`PowerBankObject_Server:120`,
                --        et `PowerBankSystem_Client:679` s'en sert déjà pour la même question) ;
                --      · 📚 Doc : `IsoGenerator.isPoweringSquare(gx,gy,gz, x,y,z)` est STATIQUE et
                --        répond « ce générateur-là couvre-t-il cette case ». `isActivated()` existe
                --        sur `IsoGenerator` (⚠️ contrairement à `IsoStove`, qui n'a que `Activated()`).
                -- ⚖️ Un générateur ÉTEINT n'alimente rien : il ne compte pas comme autre source.
                if not skip then
                    for _, g in ipairs(foreign) do
                        if IsoGenerator.isPoweringSquare(g.x, g.y, g.z, dev.x, dev.y, dev.z) then
                            skip = true
                        end
                    end
                end
                if skip then
                    skipped = skipped + 1
                else
                    member:controlDevice(dev.x, dev.y, dev.z, dev.dtype, false)
                    n = n + 1
                end
            end
        end
    end
    -- 🔴 LIBELLÉ CORRIGÉ le 2026-08-13 : il disait « switched off ». C'ÉTAIT UN MENSONGE.
    --    Le compteur incrémente à chaque COMMANDE ÉMISE, sans vérifier qu'elle a mordu — or un
    --    `dtype` sans branche dans `psrSetDeviceState` (c'était le cas de `stove`, ça reste celui
    --    d'`appliance`) traverse sans rien faire, et était compté comme éteint.
    -- 🔑 Un chiffre qui rassure sans mesurer est pire qu'aucun chiffre : c'est lui qu'on relit
    --    dans trois semaines pour clore un dossier. Le libellé dit désormais ce qu'il compte.
    -- 🚨 Journalisation gatée sur `announce` : la coupure tourne à CHAQUE passe tant que le
    --    réseau ne fournit pas, mais on n'imprime qu'au premier passage. Sans ça on réimprime
    --    à chaque tick — exactement le défaut M1 de la v1.66, publié et mesuré à ~14 400 l/h.
    -- 🚨 IMPRIMÉ MÊME À ZÉRO au 1er passage — c'est ce qui manquait au run précédent :
    --    l'absence totale de ligne laissait indiscernables « aucun appareil actif », « tous
    --    sautés par le garde-fou » et « le code ne tourne pas ». Les trois chiffres tranchent.
    -- ⚖️ Gaté sur `announce` (1er passage seulement) : la coupure, elle, tourne à chaque tick.
    --    Couper en continu, se taire en continu — défaut M1 de la v1.66, ~14 400 lignes/heure.
    if announce then
        self:noise(string.format("network stopped supplying - %d commanded off, %d skipped (other power source), %d spared (persistent-off device), %d device(s) seen",
            n, skipped, spared, seen))
    end
end

--- 🩹 MIGRATION v1.70 — RÉPARE LES SAVES ABÎMÉES PAR LA COUPE AUTOMATIQUE DE LA v1.68.
--- Les v1.68/1.69 ont gravé `fridge_off`/`freezer_off` dans des saves (et `PFR_on=false` sur des
--- Cold Units) sans qu'aucun chemin ne les relève. On les rétablit UNE FOIS par bank.
---
--- ⚖️ ARBITRAGE COMMANDEUR (2026-08-13) — assumé et dit comme tel : **rien ne distingue un frigo
---    éteint par notre bug d'un frigo éteint EXPRÈS** (par le Solar Computer ou par *Fridges Off!*).
---    Les deux produisent le même état, et les saves déjà touchées ne portent aucun marqueur de
---    nous. J'ai cherché la voie chirurgicale — filtrer sur « alimenté et pourtant off » n'aide
---    pas, les deux cas y tombent. ⇒ on rétablit, et on accepte de rallumer par erreur un appareil
---    volontairement éteint. 🔑 *Le coût d'erreur n'est pas symétrique : rallumer à tort coûte un
---    clic, ne pas rallumer coûte la nourriture d'une save entière, en silence.* C'est exactement
---    le raisonnement déjà inscrit dans le garde-fou de `cutNetworkDevices`.
---
--- 🔒 UNE SEULE FOIS, ET LE DRAPEAU DOIT SURVIVRE AU RECHARGEMENT : il vit dans le modData de
---    l'IsoObject de la bank (persisté par le moteur), **jamais** dans un champ Lua de la table.
---    Un drapeau en mémoire rejouerait la migration à CHAQUE chargement de save — ce qui rendrait
---    l'extinction volontaire d'un frigo définitivement impossible. *Une migration qui se répète
---    n'est plus une migration, c'est une règle.*
--- 🔑 Drapeau PAR BANK et non global : les banks se chargent par CHUNK (`OnChunkLoaded`), donc au
---    premier tick certaines n'existent pas encore. Un one-shot global les condamnerait en silence.
function PBSystem:restoreColdDevices(network)
    for _, member in ipairs(network) do
        local iso = member.getIsoObject and member:getIsoObject() or nil
        local md  = iso and iso.getModData and iso:getModData() or nil
        -- 🔴🔴 CORRIGÉ LE 2026-08-16 — LE DRAPEAU ÉTAIT POSÉ **AVANT** LE TRAVAIL.
        --
        -- L'ancienne forme écrivait `md.PSR_coldRestore170 = true` en **première instruction**,
        -- puis appelait `updateDrain()` et balayait. Si la liste revenait vide ou amputée — et
        -- `updateDrain` **saute silencieusement** les cases non chargées — le droit de rejouer
        -- était consommé **pour rien**, définitivement : aucun drapeau `171` n'a jamais existé.
        -- 💥 Conséquence mesurée sur le signal de `real_maurice` (15/08) : des frigos gravés
        --    `_off` par la v1.68, une migration qui s'est marquée « faite » sans les voir, et un
        --    terminal qui refusait le rattrapage manuel ⇒ **boucle fermée**.
        -- 🔑 *Un one-shot doit se marquer sur PREUVE de travail, jamais sur intention.* La forme
        --    juste existait déjà dans ce lot, 900 lignes plus loin : `psrSweepRect` rend
        --    `complete`, et l'appelant ne clôt que si `complete`. Elle n'avait pas été portée ici.
        --
        -- 🆕 **Drapeau `172`, distinct du `170`** : sans lui, le correctif ci-dessus n'atteindrait
        --    aucun des joueurs actuellement touchés — ils sont tous déjà marqués `170`. On rejoue
        --    donc **une fois**, et une seule, chez tout le monde.
        -- ⚖️ Le risque est inchangé et déjà assumé (`RISKS.md` 13/08) : un frigo éteint **exprès**
        --    peut être rallumé une fois. Rallumer à tort coûte un clic ; ne pas rallumer coûte la
        --    nourriture d'une save, en silence.
        if md and not md.PSR_coldRestore172 then
            -- Même précaution que dans `cutNetworkDevices` : `deviceList` peut être périmé si
            -- `shouldDrain()` est faux (bank éteinte) — or c'est précisément l'état concerné.
            if member.updateDrain then member:updateDrain() end
            local byType, total = {}, 0
            local seen = 0
            for _, dev in ipairs(member.deviceList or {}) do
                seen = seen + 1
                if PSR_PERSISTENT_OFF[dev.dtype] and not dev.active then
                    member:controlDevice(dev.x, dev.y, dev.z, dev.dtype, true)
                    byType[dev.dtype] = byType[dev.dtype] or {}
                    local t = byType[dev.dtype]
                    t[#t + 1] = { x = dev.x, y = dev.y, z = dev.z }
                    total = total + 1
                end
            end
            if total > 0 then
                -- 📡 `container:setType` NE SE RÉPLIQUE PAS (cf. `Commands.controlDevice`) : sans
                --    ce broadcast, en MP les autres clients garderaient l'icône « étagère » et le
                --    titre « Freezer (OFF) » jusqu'au rechargement de leur chunk. Émis à TOUS
                --    (pas de `playerObj`), et idempotent côté client.
                for dtype, coords in pairs(byType) do
                    sendServerCommand("PSR", "applyDeviceToggle", { dtype = dtype, on = true, devices = coords })
                end
                if member.saveData then member:saveData(true) end
            end
            -- 🔒 LE DRAPEAU SE POSE ICI, SUR PREUVE — et jamais sur intention.
            --   · `seen > 0`  ⇒ on a vraiment regardé la liste : qu'on ait restauré ou non, le
            --                   travail est fait, on ne rejoue plus.
            --   · `seen == 0` ⇒ on n'a **rien vu**, et ça ne prouve pas qu'il n'y a rien : la
            --                   bank peut être éteinte, ses chunks déchargés, sa liste amputée.
            --                   *Une absence d'information n'autorise pas à clore le geste.*
            --                   ⇒ on réessaie à la passe suivante, **mais borné** : sans plafond,
            --                   une bank sans aucun appareil froid rejouerait `updateDrain` à
            --                   chaque passe pour l'éternité — le défaut exact qu'on vient de
            --                   corriger sur `PSR_coverRect`, dans ce même lot.
            local tries = (md.PSR_coldRestoreTries or 0) + 1
            md.PSR_coldRestoreTries = tries
            if seen > 0 or tries >= 3 then
                md.PSR_coldRestore172   = true
                md.PSR_coldRestoreTries = nil
            end
            if total > 0 then
                self:noise(string.format("v1.72 migration - %d cooling device(s) restored, %d device(s) seen (left off by the v1.68 automatic cut)", total, seen))
            end
        end
    end
end

function PBSystem:updateNetwork(network, solaroutput)
    -- 🩹 Migration v1.70 AVANT toute autre décision de la passe : la coupe ci-dessous lit
    --    `dev.active`, et un appareil qu'on vient de rétablir doit être vu à son état neuf.
    self:restoreColdDevices(network)

    -- ⚡ TRANSITION « le réseau ne fournit plus » — les QUATRE déclencheurs convergent ici.
    -- 🔑 Extinction · démontage · dernière batterie retirée · chargement de save : aucun ne
    --    demande son propre hook. Tous changent la valeur de `bankSupplies`, et `updateNetwork`
    --    est le seul endroit qui repasse sur le réseau entier. **Un point, quatre portes.**
    -- ⚖️ Première évaluation (`nil`) traitée comme « fournissait » : au chargement d'une save
    --    où plus rien ne fournit, on éteint une fois. C'est délibéré et sans risque — on ne
    --    fait qu'éteindre ce qui n'aurait pas dû rester allumé.
    do
        local nowSupplies, was = false, false
        for _, m in ipairs(network) do
            if self:bankSupplies(m) then nowSupplies = true end
            if m.psrWasSupplying == nil or m.psrWasSupplying then was = true end
        end
        -- 🔴 CORRIGÉ le 2026-08-13 APRÈS TEST DU COMMANDEUR : *« le four se coupe bien, mais
        --    bank toujours éteinte je peux le rallumer et il ne se coupe plus jamais »*.
        -- 🔑 J'avais écrit un déclenchement SUR FRONT (`was and not nowSupplies`). Une fois la
        --    transition passée, plus rien ne se redéclenchait — tout ce que le joueur rallumait
        --    à la main restait allumé. **Or la règle du Commandeur est un ÉTAT, pas un événement** :
        --    *tant qu'aucune bank ne fournit, rien ne doit être allumé.*
        -- ⇒ On coupe à CHAQUE passe tant que le réseau ne fournit pas. Le coût est borné : cet
        --    état est anormal et bref, `deviceList` est déjà construit par `updateDrain`, et la
        --    boucle sort immédiatement quand `nowSupplies` est vrai (le cas normal).
        -- 🚨 Le `was` n'est PAS supprimé : il sert à ne journaliser que le premier passage,
        --    sinon on réimprime à chaque tick — c'est le défaut M1 de la v1.66, publié, mesuré
        --    à ~14 400 lignes/heure. **Couper en continu, se taire en continu.**
        -- 🛑 PORTE 1/2 de la coupe automatique — SUSPENDUE le 2026-08-14 (voir `PSR_AUTOCUT_ENABLED`).
        if PSR_AUTOCUT_ENABLED and not nowSupplies then self:cutNetworkDevices(network, was) end
        for _, m in ipairs(network) do m.psrWasSupplying = nowSupplies end
    end

    -- Sync battery state from containers before every tick (ISTransferAction may not fire in B42 coop)
    for _, member in ipairs(network) do
        local iso = member:getIsoObject()
        if iso then
            member:calculateBatteryStats(iso:getContainer())
            member:updateSprite()
        end
    end
    -- `R-32` (2026-08-23) : LE DRAIN DU RESEAU SE SOMME SUR L'UNION DEDOUBLONNEE.
    -- AVANT : `if not drainCounted then totalDrain = member.drain end` -- le PREMIER membre qui
    --   draine donnait son drain a tout le reseau. Mesure sur deux terminaux du meme reseau,
    --   banks a UNE case l'une de l'autre : **156,8 Ah** et **332,8 Ah**. Chaque bank ne facture
    --   que ce que SON balayage atteint => le drain dependait de l'ORDRE D'ITERATION, et un
    --   reseau pouvait etre facture de moitie (courant gratuit).
    -- APRES : on collecte les membres qui drainent, et `getNetworkBilledDrain` somme `rate` sur
    --   l'union DEDOUBLONNEE, `active and powered` -- la meme regle que `scanCellDevices`.
    -- ⚖️ Effet en jeu ASSUME (arbitrage Commandeur) : un reseau multi-banks couvrant plusieurs
    --   zones se vide desormais plus vite. C'est la fin d'un courant gratuit, pas une penalite.
    -- ⚠️ On ne compte QUE les membres dont `shouldDrain` est vrai : une bank eteinte, ou dont le
    --   generateur de secours tourne, ne facture rien -- comportement inchange.
    local totalDrain, totalPanels = 0, 0
    local draining = {}
    for _, member in ipairs(network) do
        if member:shouldDrain(member:getIsoObject()) then
            member:updateDrain()
            draining[#draining + 1] = member
        end
        totalPanels = totalPanels + (member.npanels or 0)
    end
    totalDrain = self:getNetworkBilledDrain(draining)
    local totalCharge, totalCapacity = self:getNetworkStats(network)
    local dCharge = solaroutput * totalPanels - totalDrain
    if self.updateEveryTenMinutes then dCharge = dCharge / 6 end
    local newCharge = totalCharge + dCharge
    if newCharge < 0 then newCharge = 0
    elseif newCharge > totalCapacity then newCharge = totalCapacity end
    self:distributeCharge(network, newCharge, totalCapacity)
    for _, member in ipairs(network) do
        local isoMember = member:getIsoObject()
        local memberModCharge = (member.maxcapacity or 0) > 0 and (member.charge or 0) / member.maxcapacity or 0
        if isoMember then
            member:updateBatteries(isoMember:getContainer(), memberModCharge)
            member:updateGenerator()
            member:updateSprite(memberModCharge)
        end
        member:updateConGenerator(newCharge)
        member:saveData(true)
    end
    if self.wantNoise then
        self:noise(string.format("network: %d banks, %.1f/%.1f kWh, dCharge: %.1f, panels: %d, drain: %.1f",
            #network, newCharge, totalCapacity, dCharge, totalPanels, totalDrain))
    end
end

function PBSystem.updatePowerbanks()
    local self = PBSystem.instance
    local solaroutput = self:getModifiedSolarOutput(1)
    local processed = {}
    for i = 0, self.system:getObjectCount() - 1 do
        local pb = self:getLuaObjectByIndex(i)
        local key = pb and (pb.x .. "," .. pb.y .. "," .. pb.z) or nil
        if key and not processed[key] then
            local network = self:getNetwork(pb)
            for _, member in ipairs(network) do
                processed[member.x .. "," .. member.y .. "," .. member.z] = true
            end
            self:updateNetwork(network, solaroutput)
        end
    end
end

-- B42.19 : the vanilla generator update re-flags an indoor activated generator's building as
-- toxic much more aggressively than pre-42.19 (generator system rework, 42.19 changelog #117/#119).
-- PSR's setToxic(false) in updateGenerator only runs on the charge tick (every 10 game minutes,
-- or hourly with ChargeFreq=2), which leaves long windows where players inside see a transient
-- "toxic gas" warning. Cosmetic only — the flag is cleared before damage accumulates (confirmed
-- by player report 2026-06-02 : warning visible, zero damage) — but worth suppressing properly.
-- This light tick re-clears the flag every game minute (~2.5 real seconds) so the window is
-- imperceptible. Known side effect (pre-existing since v1.8, just more frequent now) : a real
-- fuel generator running in the SAME building as a PSR bank won't gas the player either — the
-- toxic flag is building-wide and PSR can't tell who set it.
-- Trace state for suppressToxic, deliberately FILE-LOCAL and not fields on PBSystem :
-- `PBSystem` is installed as the metatable of the system's modData
-- (`setmetatable(jSystem:getModData(), PBSystem)`), so anything parked on it is
-- reachable from a persisted table. These are throwaway session counters and have no
-- business being anywhere near saved data. Reset on save reload — which is exactly the
-- scope we want: one first-pass line per session.
local toxDedupSeen = false
local toxDedupMax  = 0

function PBSystem.suppressToxic()
    local self = PBSystem.instance
    if not self then return end
    -- 2026-08-19 : ONE broadcast per BUILDING, not per BANK.
    --
    -- Measured in the engine bytecode (`javap zombie.iso.areas.IsoBuilding`) :
    --     setToxic(b) { this.isToxic = b;
    --                   if (GameServer.server) GameServer.sendToxicBuilding(cx, cy, b); }
    -- There is NO guard on a value change. And `GameServer.sendToxicBuilding` logs one
    -- line, then sends a packet to EVERY connected player. So N banks standing in the
    -- same building cost N identical log lines AND N x (players online) identical
    -- packets, every game minute — for a state that was already false.
    --
    -- Why this is safe, and why it is NOT the v1.39 mistake : v1.39 gated on
    -- `isToxic()` and therefore SKIPPED buildings, which is what re-opened the gas
    -- chamber. This skips no building — only the repeats of the same one. Within a
    -- single call every iteration runs in the SAME frame, so no client packet can be
    -- processed in between : a repeat cannot carry new information. The field write is
    -- idempotent and the packet payload is identical, so removing repeats is
    -- semantically null. The anti-gas arbitration (v1.40) is untouched.
    --
    -- THE KEY MUST NEVER COLLIDE — this was checked, not assumed. If two DIFFERENT
    -- buildings shared a key we would skip one, it would stay toxic, and that is the
    -- v1.39 gas chamber all over again. Verified in the constructor bytecode :
    --     getstatic idCount ; iconst_1 ; iadd ; putstatic idCount ; putfield id
    -- i.e. `this.id = idCount++` — a plain auto-increment, so every IsoBuilding
    -- instance holds a distinct id, player-built ones included (they are built by the
    -- same constructor). Two banks in DIFFERENT buildings therefore always yield two
    -- different keys and both get cleared.
    -- `getID()` returns an int — a primitive key, so no reliance on Java object
    -- identity as a Lua table key, and no dependency on `getDef()` being non-nil.
    -- id 0 is safe here : we test `doneBuilding[bid]` (nil/true), never `bid` itself,
    -- so the Lua "0 is truthy but `x or y` bites" trap does not apply.
    local doneBuilding = {}
    -- SEPARATE counters, on purpose. A single total cannot tell "nothing to do" from
    -- "the code never ran" — and this fix REMOVES output, so silence is exactly what
    -- success looks like. Without a trace it is indistinguishable from a fix that was
    -- never shipped.
    local banks, cleared, skipped = 0, 0, 0
    for i = 0, self.system:getObjectCount() - 1 do
        local pb = self:getLuaObjectByIndex(i)
        if pb and pb.activated then
            banks = banks + 1
            local square = pb.getSquare and pb:getSquare() or nil
            local building = square and square:getBuilding() or nil
            -- Clear UNCONDITIONALLY — do NOT gate on building:isToxic(). In MP the
            -- indoor-generator toxic re-flag happens CLIENT-side, so the server's
            -- isToxic() reads false while clients gas themselves. The server-side
            -- setToxic(false) broadcast each game minute is precisely what overrides
            -- the client re-flag (that's the cost of the "Receive Toxic Building"
            -- log lines). Gating on isToxic() (v1.39) silently re-introduced the gas
            -- chamber in MP — gas is destructive, the log lines are cosmetic. (v1.40)
            if building then
                local bid = building.getID and building:getID() or nil
                -- No usable id ⇒ fall back to the old behaviour and clear it anyway.
                -- Preserving the clear matters more than saving a packet.
                if bid == nil then
                    building:setToxic(false)
                    cleared = cleared + 1
                elseif not doneBuilding[bid] then
                    doneBuilding[bid] = true
                    building:setToxic(false)
                    cleared = cleared + 1
                else
                    skipped = skipped + 1
                end
            end
        end
    end

    -- ── TRACE ─────────────────────────────────────────────────────────────────────
    -- NOT behind getDebug(). We already carry an open item saying the 1.72 nil-net is
    -- mute in the field because its only trace needs `-debug` : a report nobody can
    -- produce is not a report. This one has to reach a server owner who never asked
    -- for anything.
    --
    -- It must also stay rare, or it becomes the very noise it removes — this runs
    -- every game minute (~2.5 s real). So we log the EVENT, never the regime :
    --   · once per session, on the first pass  -> proves the code ran at all, which a
    --     duplicate-only line could never do on a base with one bank per building ;
    --   · afterwards only when `skipped` reaches a NEW MAXIMUM -> that is a change in
    --     the world (a bank added next to another), it converges to silence on its
    --     own, and it hands us the number we could not measure from here : how many
    --     banks actually share a building on a real server.
    --
    -- Server processes only. The cost being traced does not exist anywhere else :
    -- `setToxic` broadcasts under `if (GameServer.server)`, so in solo and on clients
    -- there is no packet, no log line, and these figures would mean nothing.
    -- (BRAIN MP table : isServer() is true for a dedicated server AND for the coop
    -- host's server process — precisely the two cases where GameServer.server is set.)
    -- Keep the file's `PSR_Server: ` prefix even though this bypasses `self:noise()`
    -- (which is gated on getDebug()). An unprefixed line in a busy server log is
    -- unattributable — the owner cannot tell which mod wrote it, so it reads as noise
    -- and gets ignored, or worse, blamed on someone else.
    if isServer() then
        if not toxDedupSeen then
            toxDedupSeen = true
            toxDedupMax  = skipped
            print(string.format(
                "PSR_Server: suppressToxic first pass - banks=%d cleared=%d duplicates=%d",
                banks, cleared, skipped))
        elseif skipped > toxDedupMax then
            toxDedupMax = skipped
            print(string.format(
                "PSR_Server: suppressToxic new max duplicates=%d (banks=%d cleared=%d)",
                skipped, banks, cleared))
        end
    end
end

---B42 registration — called by Events.OnSGlobalObjectSystemInit
function PBSystem.OnSGlobalObjectSystemInit()
    local jSystem = SGlobalObjects.registerSystem("psr_powerbank")
    jSystem:setObjectModDataKeys(PBSystem.savedObjectModData)

    local o = jSystem:getModData()
    setmetatable(o, PBSystem)
    o.system = jSystem
    o.wantNoise = getDebug()
    PBSystem.instance = o
    o:initSystem()
end

Events.OnSGlobalObjectSystemInit.Add(PBSystem.OnSGlobalObjectSystemInit)

-- B42: SGlobalObjects does not fire OnObjectAdded for player-placed objects.
-- Hook the PZ event directly so freshly placed banks get registered.
-- Banks are placed as IsoMoveable — replaceIsoObjectWithGenerator converts them
-- to IsoGenerator and re-fires OnObjectAdded, which then registers them below.
local function onObjectAdded(isoObject)
    if not PBSystem.instance then return end
    local ptype = PSR.WorldUtil.getType(isoObject)
    if not ptype then return end
    if ptype == "Panel" then
        local square = isoObject:getSquare()
        local spriteName = isoObject:getTextureName()
        -- Wall panels: need a wall in the correct facing direction.
        -- For map walls: stored on the adjacent square (E for W-panel, S for N-panel).
        -- For player-built walls (IsoThumpable): stored on the panel's own square.
        -- ⚠️ 2026-08-04 — CE BLOC EST INATTEIGNABLE (audit vague 1) : l'override `placeMoveable`
        -- des sprites 6/7 n'émet volontairement pas `OnObjectAdded`. La validation réelle vit
        -- côté CURSEUR (`shared/PSR/MoveableProps.lua`), où les 3 règles ont été reportées.
        -- On le garde comme filet si un jour l'event repasse par ici — mais ne pas le croire
        -- « la » validation : il ne s'exécute pas.
        if (spriteName == "solarmod_tileset_01_6" or spriteName == "solarmod_tileset_01_7") and square then
            local cell = square:getCell()
            local x, y, z = square:getX(), square:getY(), square:getZ()
            local isWPanel = spriteName == "solarmod_tileset_01_6"
            local wallTag = isWPanel and "WallW" or "WallN"
            local wallFound = false
            -- Case adjacente. ⚠️ Le commentaire disait « map walls via IsoWall » : FAUX depuis
            -- toujours — `IsoWall` n'existe pas en 42.20 et `squareHasWall` ne reconnaît QUE
            -- les murs construits par le joueur (`IsoThumpable`). Cf. la note dans
            -- `WorldUtilities.lua:squareHasWall`.
            local adjSq = isWPanel and cell:getGridSquare(x+1, y, z) or cell:getGridSquare(x, y+1, z)
            if PSR.WorldUtil.squareHasWall(adjSq) then wallFound = true end
            -- Check panel's own square for player-built walls (IsoThumpable with WallW/WallN sprite prop)
            if not wallFound then
                local objs = square:getObjects()
                for i = 0, objs:size()-1 do
                    local obj = objs:get(i)
                    if instanceof(obj, "IsoThumpable") then
                        local sp = obj:getSprite()
                        if sp then
                            local props = sp:getProperties()
                            if props and (props:has(wallTag) or props:has("WallNW")) then
                                wallFound = true
                                break
                            end
                        end
                    end
                end
            end
            if not wallFound then
                square:transmitRemoveItemFromSquare(isoObject)
                PSR.WorldUtil.returnItemToNearbyPlayer(square, "PSR.SolarPanelWall")
                PSR.WorldUtil.notifyNearbyPlayers(square, "IGUI_PSR_WallPanel_NeedsWall")
                return
            end
        end
        -- All panels: must be placed outdoors (need sunlight)
        if square and not square:isOutside() then
            local fullType = PSR.WorldUtil.PSRPanelFullTypes[spriteName] or "PSR.SolarPanelFlat"
            square:transmitRemoveItemFromSquare(isoObject)
            PSR.WorldUtil.returnItemToNearbyPlayer(square, fullType)
            PSR.WorldUtil.notifyNearbyPlayers(square, "IGUI_PSR_Panel_OutdoorOnly")
            return
        end
        -- Wall panels: cross-rotation consistency.
        -- W panel at (x,y) ↔ N panel at (x+1,y-1). If the other rotation's square
        -- is under a roof, reject this one too (prevents rotation bypass).
        if square and (spriteName == "solarmod_tileset_01_6" or spriteName == "solarmod_tileset_01_7") then
            local cell = square:getCell()
            local x, y, z = square:getX(), square:getY(), square:getZ()
            local cx = spriteName == "solarmod_tileset_01_6" and x + 1 or x - 1
            local cy = spriteName == "solarmod_tileset_01_6" and y - 1 or y + 1
            local crossSq = cell:getGridSquare(cx, cy, z)
            if crossSq and not crossSq:isOutside() then
                local fullType = PSR.WorldUtil.PSRPanelFullTypes[spriteName] or "PSR.SolarPanelWall"
                square:transmitRemoveItemFromSquare(isoObject)
                PSR.WorldUtil.returnItemToNearbyPlayer(square, fullType)
                PSR.WorldUtil.notifyNearbyPlayers(square, "IGUI_PSR_Panel_OutdoorOnly")
                return
            end
        end
        -- Clear stale connection data whenever a panel is placed/replaced
        local modData = isoObject:getModData()
        modData.pbLinked = nil
        modData.connectDelta = nil
        isoObject:transmitModData()
        return
    end
    if ptype ~= "PowerBank" then return end
    if not instanceof(isoObject, "IsoGenerator") then
        local square = isoObject:getSquare()
        if square and square:isOutside() then
            square:transmitRemoveItemFromSquare(isoObject)
            PSR.WorldUtil.returnItemToNearbyPlayer(square, "PSR.PowerBank")
            PSR.WorldUtil.notifyNearbyPlayers(square, "IGUI_PSR_PowerBank_IndoorsOnly")
            return
        end
        -- Defer: getSprite() unreliable inside placeMoveableInternal callback
        local pending = isoObject
        local function doReplace()
            Events.OnTick.Remove(doReplace)
            if pending:getSquare() then
                PSR.WorldUtil.replaceIsoObjectWithGenerator(pending)
            end
        end
        Events.OnTick.Add(doReplace)
        return
    end
    local x, y, z = isoObject:getX(), isoObject:getY(), isoObject:getZ()
    if PBSystem.instance.system:getObjectAt(x, y, z) then return end
    PBSystem.instance:loadIsoObject(isoObject)
end
Events.OnObjectAdded.Add(onObjectAdded)

-- Disconnect panels from bank when picked up
Events.OnObjectAboutToBeRemoved.Add(function(isoObject)
    if PBSystem.instance then
        PBSystem.instance:OnObjectAboutToBeRemoved(isoObject)
    end
end)

return PBSystem
