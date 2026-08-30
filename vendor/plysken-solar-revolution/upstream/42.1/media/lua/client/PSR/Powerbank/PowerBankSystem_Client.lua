--[[
    "psr_powerbank" client system — B42 rewrite (CGlobalObjects API)
--]]

---@class PSR
local PSR = require "PSR/Utilities"
local PowerBank = require "PSR/Powerbank/PowerBankObject_Client"

---@class PowerbankSystem_Client : PowerbankSystem
local PBSystem = require("PSR/PowerBankSystem_Shared"):new({})
PBSystem.__index = PBSystem

function PBSystem:initSystem()
    PSR.PBSystem_Client = self
    if isClient() then
        Events.EveryTenMinutes.Add(PBSystem.updateBanksForClient)
        Events.EveryOneMinute.Add(PBSystem.updateSpritesLocal)
        Events.OnContainerUpdate.Add(PBSystem.onContainerUpdate)
    end

    -- 🔴 2026-08-13 — LE FILET TOXIQUE ÉTAIT MORT EN SOLO DEPUIS LA v1.66, SUR TROIS VERSIONS.
    --
    -- Il était enregistré sous `isClient()`. Or **en SOLO, `isClient()` est FAUX** (mesuré sur
    -- PFR le 2026-08-06) ⇒ ni le filet ni la dette ne s'abonnaient : **le correctif n'existait
    -- pas dans le contexte où la majorité des joueurs joue.**
    --
    -- 🔑 L'exclusion était DÉLIBÉRÉE, et ses deux justifications sont tombées le même jour :
    --   · *« la mesure du 09/08 n'a montré aucun retour du drapeau en solo »* → **3 retours
    --     mesurés en solo le 13/08** (sonde `PSRDiag_Toxic`, témoin validé), déclenchés par
    --     l'ouverture/fermeture d'une trappe. La prémisse était vraie de la mesure faite, pas
    --     du phénomène : on n'avait jamais déclenché de RECALCUL DE RÉGION.
    --   · *« les effaceurs serveur (extinction :1091, retrait :1134) font déjà le travail »* →
    --     ils couvrent l'**extinction** et le **retrait** de la bank. Ici le drapeau est reposé
    --     par un recalcul **pendant que la bank tourne**. **Autre événement, jamais couvert.**
    --
    -- ⚖️ Et c'est ce qui explique le signal de `Leon "Icepick" Trotsky` : il est en **v1.67**,
    --    donc *avec* le filet — mais **en solo**, donc **jamais protégé**. Trois mois de dossier.
    --
    -- ✅ GARDE CORRECTE : tout sauf le serveur dédié HEADLESS (aucun joueur, aucun drapeau à
    --    nettoyer). C'est l'idiome déjà employé en tête de `PowerBankSystem_Server.lua`.
    --      solo             -> isClient()=faux, isServer()=faux  -> ON
    --      hôte coop        -> isClient()=vrai, isServer()=vrai   -> ON
    --      client de dédié  -> isClient()=vrai, isServer()=faux   -> ON
    --      dédié headless   -> isClient()=faux, isServer()=vrai   -> OFF
    if isClient() or not isServer() then
        Events.OnTick.Add(PBSystem.suppressToxicLocal)
        Events.EveryOneMinute.Add(PBSystem.recordToxicDebt)
    end
    Events.EveryDays.Add(PBSystem.resetAcceptItemFunction.addItems)
end

function PBSystem:noise(message)
    if self.wantNoise then print("PSR_Client: " .. message) end
end

--------------------------------------------------------------------------------
-- FILET TOXIQUE LOCAL (v1.66) — client de dédié et hôte coop uniquement
--------------------------------------------------------------------------------
-- POURQUOI : le re-flag « toxic » d'un générateur allumé en intérieur se produit CÔTÉ
-- CLIENT (verrou DECISIONS 2026-06-07). Le serveur nettoie inconditionnellement sur
-- `EveryOneMinute` (≈ 2,5 s réelles) et c'est ce broadcast qui écrase le re-flag — mais
-- rien ne garantit que la valeur nettoyée atteigne un client distant avant qu'il n'ait
-- pris des dégâts. Ce filet ferme la fenêtre localement, là où le joueur se tient.
--
-- 📏 CE QUI EST MESURÉ, ET CE QUI NE L'EST PAS (2026-08-09, sonde `PSRDiag_Toxic`) :
--    client de dédié, bank allumée, APRÈS redémarrage serveur, **330 s réelles** :
--    **0 retour du drapeau, 0 % d'exposition**, instrument validé par auto-témoin.
--    ⇒ le défaut n'est **PAS reproduit chez nous**. Mais 4 joueurs l'ont signalé le même
--    jour, et une COURSE ne se reproduit pas sur commande : 330 s sans occurrence bornent
--    sa fréquence, elles ne la réfutent pas. Notre banc n'a par ailleurs jamais qu'UN
--    joueur, quand les leurs en ont plusieurs. ⇒ filet posé, **rien n'est annoncé comme
--    « corrigé »** tant qu'on n'a pas reproduit.
--
-- ⚖️ POURQUOI PAS LA FORME LA PLUS ÉVIDENTE : itérer toutes les banks à chaque frame
--    (ce que fait le fork `PSR-Fixed`) coûte O(banks) × 144 fps en permanence — le motif
--    exact qui a coûté 140 ms/s à PFR v1.21. Ici l'ordre des gardes fait le travail :
--    on sort sur `isToxic()` (une lecture) dans la quasi-totalité des frames, et la boucle
--    sur les banks ne tourne QUE dans le cas rare où il y a réellement une décision à prendre.
--
-- 🛑 LA GARDE QU'ON NE PEUT PAS RETIRER : nettoyer dès que le bâtiment est toxique
--    effacerait aussi les fumées d'un VRAI générateur à essence posé par le joueur — le
--    drapeau est par-bâtiment et n'appartient à personne (limitation connue depuis la v1.8).
--    On ne nettoie donc que si une bank PSR **activée** se trouve dans CE bâtiment.
--------------------------------------------------------------------------------

local TOXIC_CHECK_EVERY_MS = 250   -- 4 relevés/s : la fenêtre à fermer se compte en secondes,
                                   -- pas en frames. À 144 fps, ~35× moins d'appels qu'un OnTick nu.
local lastToxicCheckMs = 0

--------------------------------------------------------------------------------
-- v1.67 — DETTE D'EFFACEMENT : one-shot quand NOTRE bank a disparu ou s'est éteinte
--------------------------------------------------------------------------------
-- 🟢 MESURÉ LE 2026-08-12, deux processus, même seconde, trois relevés + témoin négatif :
--    ***une structure PLAYER-BUILT n'existe pas dans le monde du serveur dédié.***
--      pièce construite -> serveur : IsoBuilding=nil, BuildingDef=nil, IsoRoom=nil, roomID=-1
--      maison vanilla   -> serveur : tout présent, roomID IDENTIQUE AU BIT PRÈS à celui du client
--    ⇒ Le serveur ne peut ni poser, ni lire, ni effacer le drapeau toxique d'une pièce construite.
--    📚 Et `IsoBuilding` n'expose AUCUNE méthode de synchronisation réseau (JavaDoc lue le 12/08).
--
-- 🔴 CE QUE ÇA A RÉVÉLÉ : les correctifs écrits le 11/08 pour le signal `Kirthas` (*« even I removed
--    it and the room still full of toxic gas »*) vivent dans `PowerBankObject_Server.lua:1091`
--    (extinction) et `:1134` (retrait) — **côté serveur**. Ils opèrent donc sur un objet inexistant
--    dans une pièce construite : **inertes dans le seul type de lieu où le bug est signalé**.
--    Ils restent utiles en maison de carte, où le serveur tient bien le bâtiment. Ce bloc-ci est
--    leur jumeau CLIENT, et c'est lui qui mord dans le cas rapporté.
--
-- 🔑 POURQUOI UN ONE-SHOT SUFFIT (et pas un filet permanent de plus) : le `setToxic(true)` vanilla
--    n'est posé que sur un `IsoGenerator` **ACTIVÉ** en case non-`exterior` (bytecode
--    `WorldRegionToMetaGrid.updateSquares`, lu le 11/08). Bank retirée ou éteinte = plus aucun
--    producteur = le drapeau ne peut plus être reposé. **Un seul effacement clôt le sujet.**
--
-- 🔒 LA GARDE QUI ÉVITE D'EFFACER LES FUMÉES DE QUELQU'UN D'AUTRE : on mémorise la CASE de la bank
--    allumée qu'on a réellement vue ici. Au moment de consommer la dette, on relit cette case : si
--    elle porte encore un générateur **activé**, c'est qu'un producteur légitime a pris la place —
--    on ne touche à rien. *On n'efface que la dette qu'on a soi-même contractée.*
--    ⚖️ Mémo consommé dans TOUS les cas (one-shot strict) : une dette qui survit à sa consommation
--    finirait par effacer un jour les fumées d'un générateur à essence posé bien plus tard.
--    📌 Mémo volontairement NON persisté : le drapeau lui-même ne survit pas au rechargement (le
--    bâtiment est reconstruit, et sans générateur activé rien ne le repose) ⇒ la dette est
--    intra-session par nature, exactement comme le signal de `Kirthas`.
-- 🔑 CLÉ = LES COORDONNÉES DE LA BANK, en primitifs. Surtout PAS le bâtiment.
--    Deux raisons, toutes deux payées à l'audit du 2026-08-12 :
--    (1) une table Lua qui prend un objet **Java** pour clé en garde une **référence forte** —
--        l'entrée ne partant qu'à la consommation, un `BuildingDef` resterait retenu longtemps
--        après que le joueur a quitté la zone ;
--    (2) le repli `getID()` était pire : la mesure du même jour a prouvé que c'est un **compteur
--        statique PAR PROCESSUS** (2 côté client, 0 côté serveur pour le MÊME bâtiment). Stable
--        dans un processus, mais rien ne garantit qu'un bâtiment reconstruit au rechargement de
--        chunk reprenne le même id ⇒ une dette périmée pouvait s'apparier au **mauvais bâtiment**
--        et effacer un drapeau qui ne nous appartient pas.
--        📌 J'avais mesuré ce fait deux heures plus tôt et je l'avais **cité en commentaire juste
--        au-dessus** de la ligne fautive. *Savoir un fait et l'appliquer sont deux gestes distincts.*
--    ⇒ On mémorise la CASE, et on résout le bâtiment **au moment de consommer** — la case, elle,
--      survit à tout : c'est la pièce qui reste quand la bank est partie.
local psrToxicDebt = {}   -- "x,y,z" -> { x = , y = , z = } : case d'une bank PSR vue ALLUMÉE

local function psrDebtKey(x, y, z) return x .. "," .. y .. "," .. z end

--- Le bâtiment de `dsq` est-il celui où se tient le joueur ?
--- Double comparaison (`==` ET `getDef()`) : ce fichier documente déjà qu'on ne peut pas supposer
--- que Kahlua rende le même wrapper pour deux `IsoBuilding` obtenus par deux chemins.
local function psrSameBuilding(dsq, building, bdef)
    local db = dsq and dsq:getBuilding() or nil
    if db == nil then return false end
    if db == building then return true end
    return (bdef ~= nil) and db.getDef and (db:getDef() == bdef) or false
end

-- M1 (audit 12/08) : signature du dernier « on s'abstient » imprimé, pour n'imprimer que les
-- CHANGEMENTS d'état. Voir le print de fin de `suppressToxicLocal`.
local psrLastUntouchedSig = nil

--- 🔒 Résolution du registre de banks — **REPLI STRICT, jamais substitution** (2026-08-13).
--- ⚠️ Mise en garde du Commandeur, et elle a évité une régression : *« si notre filet fonctionne
---    en coop et en MP, ce que tu vas faire ne doit pas le casser »*. Faire lire le registre
---    SERVEUR en priorité aurait changé la source de données **sur l'hôte coop**, c'est-à-dire
---    dans le seul contexte où ce filet est validé en jeu (2 témoins nettoyés, 09/08).
--- ⇒ On garde `PBSystem.instance` comme source **primaire, inchangée**. On ne bascule sur le
---    registre serveur que s'il ne rend **RIEN** — cas du SOLO, où `updateBanksForClient` reste
---    sous `isClient()` et ne peuple donc jamais l'instance cliente.
--- ⚖️ Un contexte qui marchait garde exactement le chemin qui le faisait marcher.
--- 🔒 RESTREINT AU SOLO le 2026-08-13, après audit — arbitrage Commandeur (option A).
--- 🔴 **Ce que l'audit a trouvé, et que je t'avais annoncé comme « rien ne change » :**
---    sur un **hôte coop**, `PSR.PBSystem_Server` EXISTE (le fichier serveur n'y sort pas :
---    sa garde est `isClient() and not isServer()`). Le registre client, lui, n'est peuplé
---    que par `updateBanksForClient`, abonné à **`EveryTenMinutes`** ⇒ il restait une
---    **fenêtre de ~25 s au chargement** où le repli basculait sur le registre SERVEUR,
---    dans un contexte où ce filet est validé en jeu. Changement de comportement réel.
--- ⚠️ Et le risque n'était pas seulement la fenêtre : les deux registres portent des classes
---    DIFFÉRENTES (`PowerBankObject_Client` vs `_Server`). Appeler des objets serveur depuis
---    un handler client, au chargement, est un chemin **jamais exercé**.
--- ⚖️ *On ne prend pas un risque non mesuré dans un contexte sain pour un gain qu'on n'a pas
---    demandé.* Le défaut corrigé est **solo** ⇒ le repli est **solo**.
--- ✅ `not isClient()` est vrai en solo UNIQUEMENT (faux sur hôte coop et client de dédié)
---    ⇒ coop et dédié reprennent **exactement** le code d'avant, sans aucune fenêtre.
--- 📌 Le gain espéré en coop se réobtiendra proprement le jour où on peuplera le registre
---    client plus tôt — ça, c'est un correctif, pas un effet de bord.
--- 🔴🔴 CORRIGÉ v1.70 — LE REPLI SOLO DE LA v1.69 LEVAIT UNE EXCEPTION PAR TICK, PUBLIÉE.
---    Signalé par `The Real Slark Shady` (Steam, 42.20.2 SP) :
---    `attempted index: getModData of non-table: null`
---      → `wrapGlobalObject(PowerBankSystem_Server.lua:70)`
---      → `recordToxicDebt(PowerBankSystem_Client.lua:353)`
---
--- 🔑 LA CAUSE : **les deux registres n'ont pas la même convention d'index**, et le repli en
---    fait passer un pour l'autre. 📚 Doc lue (`zombie.globalObjects.GlobalObjectSystem`) :
---    `getObjectByIndex(int)` et `getObjectCount()` sont hérités **à l'identique** par
---    `SGlobalObjectSystem` et `CGlobalObjectSystem` ⇒ **le moteur n'a qu'UNE convention.**
---    La divergence est entièrement NÔTRE, dans nos deux wrappers :
---      · client (`:414`)  `getLuaObjectByIndex(i)` → `getObjectByIndex(i - 1)`  ⇒ **1-indexé**
---      · serveur (`:99`)  `getLuaObjectByIndex(i)` → `getObjectByIndex(i)`      ⇒ **0-indexé**
---    Les deux portent le **même nom**, donc rien à l'appel ne signale qu'on a changé de monde.
---
--- 💥 CONSÉQUENCE, et elle est double — *le correctif vedette de la v1.69 était inerte ET bruyant* :
---    les consommateurs bouclent `for i = 1, count` (convention CLIENT) sur un registre SERVEUR.
---      · `i = count` est **hors plage** ⇒ le moteur rend `null` (mesuré par la pile ci-dessus,
---        non documenté côté JavaDoc) ⇒ `wrapGlobalObject(null)` ⇒ exception **à chaque passe** ;
---      · `i = 0` n'est **jamais visité** ⇒ avec UNE seule bank — le cas solo ordinaire — la
---        boucle ne voit **aucune** bank et jette immédiatement.
---    ⇒ le filet anti-fumées, qu'on croyait enfin vivant en solo, ne l'a jamais été.
---
--- 🔑 *Deux fonctions homonymes de conventions inverses ne se rattrapent par aucune relecture :
---    le site d'appel est LITTÉRALEMENT identique dans les deux cas.* ⇒ on ne corrige donc pas
---    les boucles une par une (elles resteraient jumelles et re-divergeraient) : **le repli rend
---    désormais lui-même la convention du registre qu'il choisit**, et un seul accesseur la lit.
---@return table|nil registre, boolean zeroBased
local function psrResolveBankRegistry()
    local inst = PBSystem.instance
    if inst and inst.getLuaObjectCount and inst:getLuaObjectCount() > 0 then return inst, false end
    if not isClient() then
        local srv = PSR and PSR.PBSystem_Server
        if srv and srv.getLuaObjectCount and srv:getLuaObjectCount() > 0 then return srv, true end
    end
    return inst, false
end

--- Lit la `i`-ème bank d'un registre rendu par `psrResolveBankRegistry`, `i` allant de 1 à
--- `getLuaObjectCount()`. **Seul point du fichier autorisé à appeler `getLuaObjectByIndex`.**
--- ⚖️ Le `-1` n'est pas écrit ici « au cas où » : il rétablit la convention CLIENT sur un
---    registre serveur, exactement comme le fait le wrapper client sur le système moteur.
---@param inst table registre rendu par psrResolveBankRegistry
---@param zeroBased boolean seconde valeur rendue par psrResolveBankRegistry
---@param i number 1..count
local function psrBankByIndex(inst, zeroBased, i)
    return inst:getLuaObjectByIndex(zeroBased and (i - 1) or i)
end

function PBSystem.suppressToxicLocal()
    local inst, zeroBased = psrResolveBankRegistry()
    if not inst then return end                       -- système pas encore enregistré

    local now = getTimestampMs()
    if now - lastToxicCheckMs < TOXIC_CHECK_EVERY_MS then return end
    lastToxicCheckMs = now

    local pl = getPlayer()
    if not pl then return end
    local sq = pl:getSquare()
    if not sq then return end
    local building = sq:getBuilding()
    if not building then return end                   -- dehors : rien à nettoyer

    -- Garde décisive : dans l'immense majorité des relevés, on s'arrête ici sur une seule lecture.
    if not building:isToxic() then
        -- L'état est propre : la prochaine abstention sera une information NEUVE, donc réimprimable.
        psrLastUntouchedSig = nil
        return
    end

    -- Cas rare uniquement : ce bâtiment abrite-t-il une bank PSR allumée ?
    --
    -- 🔒 RÈGLE ASSUMÉE (arbitrage Commandeur 2026-08-09) : si une bank allumée est ici, on nettoie
    --    le drapeau **SANS CHERCHER QUI L'A POSÉ** — y compris quand un générateur à essence tourne
    --    dans la même pièce. Le drapeau `toxic` est par-BÂTIMENT et n'appartient à personne : il est
    --    techniquement impossible de distinguer nos fumées des siennes.
    --    ⚖️ J'ai d'abord recommandé l'inverse (ne pas nettoyer si un générateur essence est présent,
    --    pour préserver la mécanique vanilla). **Argument du Commandeur, meilleur** : le joueur, lui,
    --    ne peut pas faire la différence non plus — il signalera « fumées avec PSR », et CHAQUE
    --    signal coûtera un aller-retour, une demande de console, un test. Coût récurrent et certain,
    --    contre un avantage de jeu marginal qui ne pénalise que celui qui l'organise.
    --    🔑 Et le fait qui tranche : le 2026-08-09 on a mesuré qu'en pièce construite par le joueur,
    --    **même un générateur vanilla ne produit aucune fumée** — on ne sait donc pas dans quelles
    --    conditions le drapeau apparaît réellement. *Écrire une règle fine pour discriminer un
    --    phénomène qu'on n'arrive pas à observer, c'est supposer ; la règle simple ne suppose rien.*
    --    📢 Contrepartie obligatoire : c'est ANNONCÉ dans la description Steam. Un avantage non
    --    documenté revient toujours par une autre porte.
    --
    -- ⚠️ Comparaison des bâtiments : `==` sur deux `IsoBuilding` obtenus par deux chemins suppose
    --    que Kahlua rende le même wrapper — jamais vérifié chez nous. On double donc par `getDef()`.
    --    Tant que le filet n'a pas été VU nettoyer en jeu, il reste un correctif non exercé.
    local nBanks, nActive, nSameBuilding = inst:getLuaObjectCount(), 0, 0
    local bdef = building.getDef and building:getDef() or nil
    for i = 1, nBanks do
        local pb = psrBankByIndex(inst, zeroBased, i)
        -- 🔴 2026-08-13 — LE CHAMP `activated` A DIVERGÉ DE L'OBJET, ET LE FILET S'EST ABSTENU DESSUS.
        --    Mesuré : `left untouched (banks=5 active=0 …)` **à la seconde même** où le capteur lisait
        --    `GEN @10822,10330,0 allume=true | type=PSR.PowerBank`. **Notre registre dit éteint,
        --    l'objet du monde dit allumé.** Écart ***stocké → réel*** : le vanilla teste
        --    `IsoGenerator.isActivated()`, nous testions un champ Lua qui ne le suivait plus.
        -- ✅ FORME ADDITIVE, JAMAIS SUBSTITUTIVE (mise en garde du Commandeur) : on accepte la bank
        --    si le champ **OU** l'objet dit allumé. ⇒ un contexte où le champ est juste continue de
        --    passer par lui — coop et dédié lisent le registre CLIENT, où le filet a réellement
        --    nettoyé deux témoins le 09/08, donc `active` y était vrai. **Rien de ce qui marchait
        --    ne change de chemin** ; le solo, qui lit le registre serveur, passe par l'objet.
        local iso = pb and pb:getIsoObject() or nil
        local isOn = (pb and pb.activated)
                     or (iso and iso.isActivated and iso:isActivated())
                     or false
        if isOn then
            nActive = nActive + 1
            local psq = iso and iso:getSquare() or nil
            local pbuild = psq and psq:getBuilding() or nil
            local sameById = (pbuild ~= nil) and (bdef ~= nil)
                             and (pbuild.getDef and pbuild:getDef() == bdef) or false
            local sameByRef = (pbuild ~= nil) and (pbuild == building)
            if sameById or sameByRef then
                nSameBuilding = nSameBuilding + 1
                building:setToxic(false)
                -- Trace NON gatée, et c'est délibéré : l'événement est rare par construction
                -- (on n'arrive ici que si le bâtiment était réellement toxique), donc zéro spam.
                -- 🔑 Payé le 2026-08-09 : la sonde a vu le drapeau revenir 4,9 s, et rien dans les
                -- logs ne permettait de dire si le filet avait agi, s'était abstenu à raison
                -- (générateur à essence sans bank), ou n'avait jamais tourné. Un correctif MUET
                -- est indiscernable d'un correctif ABSENT — et c'est cette ligne qui, chez un
                -- joueur qui signalera des fumées, dira laquelle des trois s'est produite.
                print(("PSR: toxic flag cleared locally at %d,%d,%d (bank in this building)")
                    :format(psq:getX(), psq:getY(), psq:getZ()))
                return
            end
        end
    end

    -- ── v1.67 : la DETTE. Aucune bank allumée ici MAINTENANT, mais en avions-nous une ? ──────────
    -- C'est le cas de `Kirthas` : « even I removed it and the room still full of toxic gas ».
    -- ⚠️ Le mémo ne peut PAS être alimenté seulement quand on efface : si le drapeau est posé au
    --    chargement de chunk pendant que le joueur est ailleurs, et qu'il retire la bank avant de
    --    revenir, on n'aura jamais vu de bank allumée ici. D'où `recordToxicDebt` sur EveryOneMinute,
    --    qui enregistre indépendamment de la position du joueur.
    -- On cherche une dette dont la CASE appartient à CE bâtiment. Le bâtiment n'est jamais une clé :
    -- il est résolu ici, à partir d'une case, au moment où l'on en a besoin.
    for k, debt in pairs(psrToxicDebt) do
        local dsq = getSquare(debt.x, debt.y, debt.z)
        if psrSameBuilding(dsq, building, bdef) then
            psrToxicDebt[k] = nil   -- one-shot STRICT : consommé quoi qu'il arrive (voir l'en-tête)
            -- La case de notre ancienne bank porte-t-elle encore un générateur ACTIVÉ ? Si oui, un
            -- producteur légitime a pris la place — ce ne sont plus nos fumées, on n'y touche pas.
            local ogen = dsq.getGenerator and dsq:getGenerator() or nil
            if ogen and ogen:isActivated() then
                print(("PSR: toxic debt at %d,%d,%d dropped - an ACTIVATED generator still sits there")
                    :format(debt.x, debt.y, debt.z))
            else
                building:setToxic(false)
                -- Trace distincte de celle du filet v1.66 : deux parades, deux branches, et c'est le
                -- log qui doit dire laquelle a mordu (leçon du 2026-08-11 sur le ronron — sans traces
                -- séparées, on crédite la mauvaise parade et on grave une fausse explication).
                print(("PSR: toxic flag cleared ONCE at %d,%d,%d (our bank is gone or off - debt settled)")
                    :format(debt.x, debt.y, debt.z))
            end
            psrLastUntouchedSig = nil   -- l'état vient de changer
            return
        end
    end

    -- On est ici : le bâtiment EST toxique, aucune bank allumée n'y a été trouvée, et nous n'y
    -- avons aucune dette. C'est le cas légitime du générateur à essence du joueur — on n'y touche pas.
    -- La trace dit POURQUOI on s'abstient, et c'est elle qui distinguera « garde qui protège
    -- le vanilla » de « comparaison de bâtiments qui échoue toujours », les deux produisant
    -- exactement le même silence. Rare par construction, donc sans coût.
    -- 🔴 M1 (audit 2026-08-12) — CE PRINT ÉTAIT NON THROTTLÉ, ET C'EST DU CODE PUBLIÉ (v1.66).
    -- Mesuré dans le log du jour : trois lignes à 09:28:09.895 / .10.146 / .10.396, soit EXACTEMENT
    -- la cadence de TOXIC_CHECK_EVERY_MS. Scénario entièrement légitime : un générateur à ESSENCE
    -- tourne à l'intérieur (le cas même pour lequel le mécanisme toxique existe), le joueur est dans
    -- le bâtiment, aucune bank PSR ici ⇒ le drapeau reste vrai tant que le générateur tourne, la
    -- garde `isToxic()` ne sort plus jamais, et on imprime **4 lignes/seconde indéfiniment**
    -- (~14 400/heure) chez tous les abonnés en client de dédié ou hôte coop.
    -- 🔑 Pourquoi la relecture ne l'avait pas vu : le commentaire d'origine justifiait l'absence de
    --    garde par « rare par construction ». Vrai d'un drapeau TRANSITOIRE, faux d'un générateur qui
    --    tourne des heures. *La justification décrivait le cas qu'on avait en tête, pas le domaine
    --    de la fonction.*
    -- ✅ On n'imprime plus que les CHANGEMENTS d'état : la valeur diagnostique est dans la
    --    transition, jamais dans la répétition. La signature est remise à nil dès que le bâtiment
    --    redevient sain ou qu'une dette est réglée, donc une nouvelle occurrence se réimprime.
    -- `debts` est LE chiffre qui sépare les deux causes d'un `cleared ONCE` absent :
    --   debts=0  ⇒ aucune dette n'a jamais été enregistrée (la bank n'a pas été allumée assez
    --              longtemps, ou pas allumée du tout, ou elle était dehors)
    --   debts>0  ⇒ des dettes existent et AUCUNE n'a été appariée à ce bâtiment ⇒ c'est
    --              l'appariement qu'il faut instruire, pas l'enregistrement
    local nDebts = 0
    for _ in pairs(psrToxicDebt) do nDebts = nDebts + 1 end

    local sig = ("%s|%d|%d|%d|%d"):format(bdef and tostring(bdef) or "nodef", nBanks, nActive, nSameBuilding, nDebts)
    if psrLastUntouchedSig ~= sig then
        psrLastUntouchedSig = sig
        print(("PSR: toxic building, no PSR bank found here - left untouched (banks=%d active=%d sameBuilding=%d debts=%d)")
            :format(nBanks, nActive, nSameBuilding, nDebts))
    end
end

--------------------------------------------------------------------------------
-- v1.67 — ALIMENTATION DE LA DETTE (client), indépendante de la position du joueur
--------------------------------------------------------------------------------
-- Tourne sur `EveryOneMinute` (~2,5 s de temps RÉEL), à l'échelle O(banks) — le même ordre que
-- `updateSpritesLocal` qui tourne déjà sur ce tick. On n'ajoute pas de boucle par frame.
-- 🔑 Enregistre la CASE, pas seulement le bâtiment : c'est elle qui permettra, au moment d'effacer,
--    de vérifier qu'un autre producteur n'a pas pris la place. Voir l'en-tête du bloc « DETTE ».
function PBSystem.recordToxicDebt()
    -- Même repli strict que `suppressToxicLocal` : sans lui, la dette resterait muette en SOLO
    -- (registre client jamais peuplé) — ce qui était le cas depuis la v1.67. 🧬 *Corriger un cas,
    -- c'est balayer sa famille* : les deux consommateurs du registre partagent la même faille.
    local inst, zeroBased = psrResolveBankRegistry()
    if not inst then return end
    for i = 1, inst:getLuaObjectCount() do
        local pb = psrBankByIndex(inst, zeroBased, i)
        -- 🧬 Jumeau du test additif de `suppressToxicLocal` — *corriger un cas, c'est balayer sa
        --    famille* : les deux fonctions lisaient `pb.activated`, donc les deux s'abstenaient
        --    quand le champ divergeait de l'objet. Corriger la première seule aurait laissé la
        --    dette muette, et on aurait cru le correctif complet.
        local iso = pb and pb:getIsoObject() or nil
        local isOn = (pb and pb.activated)
                     or (iso and iso.isActivated and iso:isActivated())
                     or false
        if isOn then
            local sq  = iso and iso:getSquare() or nil
            -- Chunk non chargé ⇒ pas de case, donc pas de drapeau posé non plus : rien à mémoriser.
            -- On n'enregistre que si la bank est DANS un bâtiment : dehors, le `setToxic` vanilla
            -- ne se déclenche pas (il exige une case non-`exterior`), donc il n'y a pas de dette.
            local b   = sq and sq:getBuilding() or nil
            if b then
                local x, y, z = sq:getX(), sq:getY(), sq:getZ()
                local k = psrDebtKey(x, y, z)
                -- Trace à la CRÉATION seulement, jamais au rafraîchissement : cette fonction tourne
                -- toutes les ~2,5 s réelles, une trace inconditionnelle serait du spam (M1 encore).
                -- 🔴 Pourquoi elle existe (passe coop du 2026-08-12) : sans elle, l'absence de
                --    `cleared ONCE` était **indiscernable** entre « aucune dette enregistrée » et
                --    « dette enregistrée mais non appariée au bâtiment ». J'avais appliqué la règle
                --    « un correctif muet est indiscernable d'un correctif absent » à l'effaceur,
                --    et oublié l'ENREGISTREUR — la moitié qui décide de tout le reste.
                if psrToxicDebt[k] == nil then
                    print(("PSR: toxic debt recorded at %d,%d,%d (bank is ON and indoors)")
                        :format(x, y, z))
                end
                psrToxicDebt[k] = { x = x, y = y, z = z }
            end
        end
    end
end

---Wrap a global object's mod data with PowerBank methods. Safe to call multiple times.
---@param globalObject table
---@return PowerBankObject_Client
function PBSystem:wrapGlobalObject(globalObject)
    -- 🛡️ FILET — PORTÉ DEPUIS LE JUMEAU SERVEUR LE 2026-08-16.
    -- La v1.70 avait ajouté cette garde à `PowerBankSystem_Server:wrapGlobalObject` après une
    -- exception PAR TICK publiée chez des joueurs (`getObjectByIndex` rend `null` hors plage,
    -- comportement non documenté côté JavaDoc). **Elle n'a jamais été portée ici** — alors que la
    -- pile du joueur désignait justement le couple `wrapGlobalObject` ← `recordToxicDebt`, et que
    -- `recordToxicDebt` est une fonction CLIENTE.
    -- 🔑 Une trace unique, pas une par appel : un filet bavard remplace une exception par une
    --    inondation, ce qui n'est pas un progrès.
    if not globalObject then
        if not self.psrWarnedNilGlobal then
            self.psrWarnedNilGlobal = true
            self:noise('wrapGlobalObject called with nil (caller used an out-of-range index)')
        end
        return nil
    end
    local pb = globalObject:getModData()
    if getmetatable(pb) ~= PowerBank then
        pb.x = globalObject:getX()
        pb.y = globalObject:getY()
        pb.z = globalObject:getZ()
        pb.luaSystem = self
        setmetatable(pb, PowerBank)
    end
    return pb
end

---@param x number
---@param y number
---@param z number
---@return PowerBankObject_Client?
function PBSystem:getLuaObjectAt(x, y, z)
    local go = self.system:getObjectAt(x, y, z)
    if go then return self:wrapGlobalObject(go) end
end

---@param i number  (1-indexed)
---@return PowerBankObject_Client
function PBSystem:getLuaObjectByIndex(i)
    return self:wrapGlobalObject(self.system:getObjectByIndex(i - 1))
end

---@return number
function PBSystem:getLuaObjectCount()
    return self.system:getObjectCount()
end

---@param square IsoGridSquare
---@return PowerBankObject_Client?
function PBSystem:getLuaObjectOnSquare(square)
    if not square then return end
    return self:getLuaObjectAt(square:getX(), square:getY(), square:getZ())
end

---Send a command to the server system.
---@param player IsoPlayer
---@param commandName string
---@param args table
function PBSystem:sendCommand(player, commandName, args)
    self.system:sendCommand(commandName, player, args)
end

---@param x number
---@param y number
---@param z number
function PBSystem:newLuaObjectAt(x, y, z)
    self:noise("adding luaObject " .. x .. "," .. y .. "," .. z)
    local globalObject = self.system:newObject(x, y, z)
    self.processNewLua:addItem(x, y, z)
    return self:wrapGlobalObject(globalObject)
end

do
    local o = PSR.delayedProcess:new{maxTimes=999}

    -- 2026-08-11 — DEUX TRAVAUX SANS RAPPORT PARTAGEAIENT UNE GARDE, ET LE 2ᵉ EN ÉTAIT OTAGE.
    --
    -- Forme d'avant : la désinscription du générateur de la liste de process du cell était
    -- **imbriquée dans `if c then`** (conteneur prêt), alors que l'entrée était retirée de la
    -- file (`table.remove`) **quoi qu'il arrive**. Conteneur pas encore prêt à ce passage ⇒ la
    -- désinscription n'était **jamais faite et jamais réessayée**, malgré `maxTimes = 999`.
    --
    -- 💥 CE QUE ÇA COÛTAIT : `IsoGenerator.update()` ne joue la boucle « générateur en marche »
    -- que si l'objet est dans cette liste. PSR l'en retire à **5 endroits** (MapObjects,
    -- RandomWorldSpawns, loadGenerator, WorldUtilities, ici) — c'est pour ça qu'une bank
    -- rechargée depuis un chunk est silencieuse. Sur une **POSE**, ce retrait-ci était le seul
    -- côté client, et il lâchait ⇒ **ronron de groupe électrogène jusqu'à la reconnexion**.
    -- 🗣️ Symptôme signalé par 3 joueurs (`poedgirl` 08/08 — *« Once started, the generator noise
    -- is going constantly »* —, `Kirthas` et `Sir Bearington` le 11/08), et reproduit par le
    -- Commandeur : *« on pose la bank, on l'allume ça fait du son, on quitte et on rejoint, plus
    -- de bruit »*. **La pose, confirmée en jeu — pas l'activation.**
    -- 🧬 La parade était écrite 5 fois et manquait exactement là où le joueur passe à chaque pose.
    --
    -- ✅ Forme corrigée : la désinscription ne dépend **plus** du conteneur, et l'entrée n'est
    -- retirée de la file que lorsque **les deux** travaux sont faits. Le drapeau `dereg` évite
    -- de rappeler `addToProcessIsoObjectRemove` à chaque passage tant qu'on attend le conteneur.
    function o.process()
        if not o.data then return o:stop() end
        for i = #o.data, 1, -1 do
            local e   = o.data[i]
            local gen = e.sq:getGenerator()
            if gen then
                if not e.dereg then
                    gen:getCell():addToProcessIsoObjectRemove(gen)
                    e.dereg = true
                    -- Trace NON gatée : l'événement est rare (une pose de bank), donc zéro spam,
                    -- et c'est elle qui dira, chez un joueur qui signale du bruit, si le retrait
                    -- a eu lieu ou non. Sans elle, correctif absent et correctif muet se
                    -- ressemblent exactement.
                    print(("PSR: bank generator removed from cell process list at %d,%d,%d (no engine hum)")
                        :format(e.sq:getX(), e.sq:getY(), e.sq:getZ()))
                end
                local isoPb = PBSystem.instance:getIsoObjectOnSquare(e.sq)
                local c     = isoPb and isoPb:getContainer() or nil
                if c then
                    c:setAcceptItemFunction("AcceptItemFunction.PSR_Batteries")
                    table.remove(o.data, i)   -- les DEUX travaux sont faits
                end
                -- conteneur pas encore prêt : on GARDE l'entrée et on repasse (c'était le trou).
            end
        end
        if #o.data == 0 or o.times <= 1 then o:stop() return end
        o.times = o.times - 1
    end

    function o:addItem(x, y, z)
        local square = getSquare(x, y, z)
        if not square then return end
        if not self.data then
            self.data = {}
            self:start()
        end
        self.times = self.maxTimes
        table.insert(self.data, { sq = square, dereg = false })
    end

    PBSystem.processNewLua = o
end

do
    local o = PSR.delayedProcess:new{maxTimes=999}

    function o.process()
        if not o.data then return o:stop() end
        for i = #o.data, 1, -1 do
            local obj = o.data[i]
            if obj:getObjectIndex() == -1 then
                table.remove(o.data, i)
            else
                local container = obj:getContainer()
                if container == nil then
                    table.remove(o.data, i)
                elseif container:getAcceptItemFunction() == nil then
                    PBSystem.instance:noise("Container reset")
                    container:setAcceptItemFunction("AcceptItemFunction.PSR_Batteries")
                    triggerEvent("OnContainerUpdate", obj)
                    table.remove(o.data, i)
                    local players = IsoPlayer.getPlayers()
                    for j = 0, players:size() - 1 do
                        local player = players:get(j)
                        if player ~= nil and player:getZ() == obj:getZ()
                            and IsoUtils.DistanceToSquared(player:getX(), player:getY(), obj:getX() + 0.5, obj:getY() + 0.5) <= 4 then
                            ISTimedActionQueue.clear(player)
                        end
                    end
                else
                    table.remove(o.data, i)
                end
            end
        end
        if #o.data == 0 or o.times <= 1 then return o:stop() end
        o.times = o.times - 1
    end

    function o.addItems()
        o.data = {}
        for i = 1, PBSystem.instance:getLuaObjectCount() do
            local isoObject = PBSystem.instance:getLuaObjectByIndex(i):getIsoObject()
            if isoObject then
                table.insert(o.data, isoObject)
            end
        end
        if #o.data > 0 then
            o.times = o.maxTimes
            o:start()
        else
            o.data = nil
        end
    end

    PBSystem.resetAcceptItemFunction = o
end

function PBSystem.canConnectPanelTo(panel)
    local options = {}
    local sq = panel:getSquare()
    if not sq then return options end
    if not sq:isOutside() then
        options.inside = true
        return options
    end
    local x = panel:getX()
    local y = panel:getY()
    local z = panel:getZ()
    local abs = math.abs
    local jSystem = PBSystem.instance.system
    -- 2026-08-06 : was `<= 400.0` / `<= 3` hard-coded, the exact twin of the server's
    -- `PowerBank:getPanelStatus`. Read once, outside the loop (the value cannot change
    -- mid-scan and re-reading it per bank would be wasted work).
    local area = PSR.WorldUtil.getPanelConnectArea()
    for i = 0, jSystem:getObjectCount() - 1 do
        local pb = PBSystem.instance:wrapGlobalObject(jSystem:getObjectByIndex(i))
        local dx, dy = pb.x - x, pb.y - y
        if dx*dx + dy*dy <= area.distance and abs(z - pb.z) <= area.levels then
            pb:updateFromIsoObject()
            local isConnected
            for _, ipanel in ipairs(pb.panels or {}) do
                if x == ipanel.x and y == ipanel.y and z == ipanel.z then
                    isConnected = true
                    break
                end
            end
            table.insert(options, { pb, pb.x - x, pb.y - y, isConnected })
        end
    end
    return options
end

function PBSystem.getGeneratorsInAreaInfo(luaPb, area)
    local DistanceToSquared = IsoUtils.DistanceToSquared
    local generators = 0
    for ix = luaPb.x - area.radius, luaPb.x + area.radius do
        for iy = luaPb.y - area.radius, luaPb.y + area.radius do
            for iz = luaPb.z - area.levels, luaPb.z + area.levels do
                local sq = getSquare(ix, iy, iz)
                local generator = sq and luaPb.luaSystem:getValidBackupOnSquare(sq)
                if generator and DistanceToSquared(luaPb.x, luaPb.y, luaPb.z, ix, iy, iz) <= area.distance then
                    generators = generators + 1
                end
            end
        end
    end
    return generators
end

-- OnContainerUpdate fires with the IsoObject (parent), not the ItemContainer
function PBSystem.onContainerUpdate(isoObject)
    if not isoObject then return end
    local pb = PBSystem.instance:getLuaObjectAt(isoObject:getX(), isoObject:getY(), isoObject:getZ())
    if not pb then return end
    local itemContainer = isoObject:getContainer()
    if not itemContainer then return end
    local batteries, capacity, charge = 0, 0, 0
    local items = itemContainer:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local maxCap = item:getModData().PSR_maxCapacity
        if maxCap then
            local cond = item:getCondition()
            if cond > 0 then
                batteries = batteries + 1
                local cap = maxCap * (1 - math.pow((1 - (cond / 100)), 6))
                capacity = capacity + cap
                charge = charge + cap * item:getCurrentUsesFloat()
            end
        end
    end
    pb.batteries = batteries
    pb.maxcapacity = capacity
    pb.charge = charge
    pb:updateSprite()
end

-- Sprite-only fallback: re-reads local container each minute in case OnContainerUpdate didn't fire
function PBSystem.updateSpritesLocal()
    for i = 1, PBSystem.instance:getLuaObjectCount() do
        local pb = PBSystem.instance:getLuaObjectByIndex(i)
        local isopb = pb:getIsoObject()
        if isopb then
            local itemContainer = isopb:getContainer()
            if itemContainer then
                local batteries, capacity, charge = 0, 0, 0
                local items = itemContainer:getItems()
                for v = 0, items:size() - 1 do
                    local item = items:get(v)
                    local maxCap = item:getModData().PSR_maxCapacity
                    if maxCap then
                        local cond = item:getCondition()
                        if cond > 0 then
                            batteries = batteries + 1
                            local cap = maxCap * (1 - math.pow((1 - (cond / 100)), 6))
                            capacity = capacity + cap
                            charge = charge + cap * item:getCurrentUsesFloat()
                        end
                    end
                end
                pb.batteries = batteries
                pb.maxcapacity = capacity
                pb.charge = charge
                pb:updateSprite()
            end
        end
    end
end

---NOTE (suivi docs/RISKS.md 2026-06-19) : peut tourner avant réception des données serveur ; idéalement piloter par commande. Inoffensif (lecture modData en retard d'un tick au pire).
function PBSystem.updateBanksForClient()
    for i = 1, PBSystem.instance:getLuaObjectCount() do
        local pb = PBSystem.instance:getLuaObjectByIndex(i)
        local isopb = pb:getIsoObject()
        if isopb then
            pb:fromModData(isopb:getModData())
            pb:updateSprite()
            pb:updateGenerator()
            local itemContainer = isopb:getContainer()
            if itemContainer then
                local mc = pb.maxcapacity or 0
                local delta = mc > 0 and (pb.charge or 0) / mc or 0
                local items = itemContainer:getItems()
                for v = 0, items:size() - 1 do
                    local item = items:get(v)
                    if item:getModData().PSR_maxCapacity then
                        item:setCurrentUsesFloat(delta)
                    end
                end
            end
        end
    end
end

function PBSystem:OnChunkLoaded(wx, wy)
    local globalObjects = self.system:getObjectsInChunk(wx, wy)
    for i = 1, globalObjects:size() do
        self:wrapGlobalObject(globalObjects:get(i - 1))
    end
    self.system:finishedWithList(globalObjects)
end

---B42 registration — called by Events.OnCGlobalObjectSystemInit
function PBSystem.OnCGlobalObjectSystemInit()
    local jSystem = CGlobalObjects.registerSystem("psr_powerbank")

    local o = jSystem:getModData()
    setmetatable(o, PBSystem)
    o.system = jSystem
    o.wantNoise = getDebug()
    PBSystem.instance = o
    o:initSystem()
end

Events.OnCGlobalObjectSystemInit.Add(PBSystem.OnCGlobalObjectSystemInit)

--------------------------------------------------------------------------------
-- CEINTURE — désinscription à l'ARRIVÉE de l'objet, sans passer par la file (2026-08-11)
--------------------------------------------------------------------------------
-- Le correctif de `processNewLua` ci-dessus répare la garde qui lâchait, mais il suppose que
-- la pose passe par `newLuaObjectAt` **sur le client**. Sur une pose distante, l'ordre est :
-- `WorldUtilities.lua:265` transmet l'objet aux clients, **PUIS** `:269` le désinscrit — de la
-- liste **du serveur**. Le client, lui, reçoit l'objet, fait son propre `addToWorld()` (qui
-- l'INSCRIT), et rien de garanti ne l'en retire.
-- ⚖️ Je n'ai pas mesuré laquelle des deux branches lâche chez le joueur, et le correctif est
--    le même dans les deux cas : désinscrire dès qu'un générateur À NOUS apparaît côté client.
--    *Deux chemins vers le même défaut, une seule parade — et chacun trace, donc le prochain
--    log dira lequel a servi.*
--
-- 🎯 `OnObjectAdded` est le bon événement, et c'est notre propre cookbook qui le dit : côté
--    client il ne fire **que pour les placements live**, jamais pour les chunks streamés — or
--    une bank streamée est déjà silencieuse. L'événement couvre donc exactement le cas fautif.
-- ⏱️ Report d'un tick obligatoire : dans `OnObjectAdded`, `getSprite()` est nil sur un objet
--    fraîchement posé (piège B42 connu) et le container n'est pas attaché.
-- 🛑 GARDE STRICTE, et c'est elle qui compte : on ne désinscrit QUE nos propres banks.
--    Désinscrire un vrai groupe électrogène vanilla lui retirerait sa combustion, sa condition et
--    son rayon électrique — une régression bien pire que le bruit qu'on corrige.
--
-- 🔴🔴 CORRIGÉ LE 2026-08-16 — CE COMMENTAIRE AFFIRMAIT UNE PRÉMISSE DÉJÀ RÉFUTÉE.
--    Il disait : *« tag posé par PSR seul (3 sites, tous à nous) »*, et le code testait donc la
--    **PRÉSENCE** de `md.generatorFullType`. **`generatorFullType` est un champ VANILLA** : le
--    moteur l'écrit lui-même sur tout `IsoGenerator` construit depuis un item.
-- 📌 Mesuré en jeu le **13/08** — six mots du Commandeur (*« j'ai qu'une bank »*) contre une sonde
--    qui annonçait « 2 vus dont 2 à nous » — et le jumeau **serveur** a été corrigé le jour même
--    pour tester la **VALEUR** (`PowerBankSystem_Server.lua`, `gft == "PSR.PowerBank"` ou membre de
--    `PSRFullTypes`). **La correction n'a jamais été portée ici.**
-- 💥 Portée : gaté par `isClient()`, donc **solo indemne** ; sur **hôte coop** il n'y a qu'un
--    processus et une seule `cell`, donc le générateur à essence d'un joueur y était réellement
--    désinscrit de la liste de process du cell.
-- 🧬 *Corriger un cas, c'est balayer sa famille* — et le jumeau ne fait pas mal ENCORE, donc rien
--    ne le signale. → [[feedback-corriger-un-cas-balayer-la-famille]]
if isClient() then
    local function silenceIfPSRBank(obj)
        if not obj or not instanceof(obj, "IsoGenerator") then return end
        local md = obj.getModData and obj:getModData() or nil
        local gft = md and md.generatorFullType or nil
        if not gft then return end
        -- Le discriminant est la VALEUR, jamais la présence. Forme recopiée du jumeau serveur.
        local ours = (gft == "PSR.PowerBank")
        if not ours then
            for _, psrFull in pairs(PSR.WorldUtil and PSR.WorldUtil.PSRFullTypes or {}) do
                if gft == psrFull then
                    ours = true
                    break
                end
            end
        end
        if not ours then return end   -- générateur d'autrui : on n'y touche pas
        local cell = obj.getCell and obj:getCell() or nil
        local sq   = obj.getSquare and obj:getSquare() or nil
        if not cell or not sq then return end
        cell:addToProcessIsoObjectRemove(obj)
        print(("PSR: bank generator removed from cell process list at %d,%d,%d (OnObjectAdded belt)")
            :format(sq:getX(), sq:getY(), sq:getZ()))
    end

    Events.OnObjectAdded.Add(function(isoObject)
        local pending = isoObject
        local function deferred()
            Events.OnTick.Remove(deferred)
            silenceIfPSRBank(pending)
        end
        Events.OnTick.Add(deferred)
    end)
end

return PBSystem
