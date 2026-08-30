require "ISUI/ISCollapsableWindow"
local PSR = require "PSR/Utilities"

---@class PSRComputerPanel : ISCollapsableWindow
local PSRComputerPanel = ISCollapsableWindow:derive("PSRComputerPanel")

-- Layout — base values calibrated for UIFont.Small at default Font Size (~14 px).
-- Real positions are scaled at runtime via computeLayout() to respect the player's
-- in-game Font Size setting (Options > Display > Font Size). Without scaling, text
-- bleeds across columns at Font Size 24+ (bug reported by Workshop player).
-- 🎨 REFONTE 2026-08-07 — « variante A : phosphore ambre », maquette validée par le Commandeur.
--    La fenêtre passe de 460×~330 à **760×560** et de **12 à 16 lignes par page** : une base
--    ordinaire tient désormais en 2 pages au lieu de 3. Le gain est fonctionnel, pas décoratif.
--    ⚠️ SEUL LE RENDU CHANGE. Le double chemin solo/dédié, la pagination, les boutons et les
--    horloges (proximité ~2 s, lien ~0,5 s, auto-refresh 10 s) sont INTACTS — ils sont testés
--    (campagne MP 2026-08-07, 12/12) et une refonte visuelle n'est pas une raison de les rouvrir.
local ROWS_PER_PAGE   = 16
local FUEL_TO_AH      = 800   -- matches PowerBank.fuelToSolarRate (L/h → Ah/h)
local BASE_FONT_H     = 14
local BASE_ROW_H      = 26
local BASE_WIN_W      = 760
local BASE_COL_EXPAND = 10    -- expand/collapse button (width 18 scaled)
local BASE_COL_TYPE   = 38    -- device type name or indented coords
local BASE_COL_COUNT  = 330   -- active count "(on/total)" or "(n)"
local BASE_COL_DRAIN  = 420   -- drain in Ah
local BASE_COL_STATUS = 510   -- ON / OFF / PARTIAL text
local BASE_COL_BTN    = 610   -- group toggle button
local BASE_COL_GO     = 608   -- "Go" button on device rows
local BASE_COL_DEVBTN = 648   -- Disable/Enable on device rows

-- ── Palette phosphore ──────────────────────────────────────────────────────────────────────
local PHOS    = { r = 0.941, g = 0.663, b = 0.235 }
local PHOS_HI = { r = 1.000, g = 0.831, b = 0.537 }
local OKC     = { r = 0.435, g = 0.851, b = 0.541 }
local NOC     = { r = 0.878, g = 0.392, b = 0.361 }
local SCRBG   = { r = 0.043, g = 0.047, b = 0.039 }
local BZ_TOP  = { r = 0.227, g = 0.212, b = 0.188 }
local BZ_BOT  = { r = 0.165, g = 0.153, b = 0.141 }
local SCAN_PITCH = 3

-- Device types that can be physically toggled on/off
-- 🔴 2026-08-13 — LA TROISIÈME LISTE DE LA FAMILLE, et c'est une CAPTURE D'ÉCRAN qui l'a révélée.
--    J'avais comparé « dtypes produits » (12) à « dtypes traités » (10) et câblé les 2 manquants
--    côté serveur ET client — en croyant la famille close. Elle comptait TROIS listes : celle-ci
--    décide de l'affichage du bouton [Enable], et `stove` n'y étant pas, le joueur voyait sa ligne
--    « Stove — OFF » **sans aucun moyen de l'allumer**. Invisible dans le code que je relisais.
-- 🔑 C'est l'axe 8 « promesse ↔ réalité » du méga audit : *le défaut ne se voyait qu'à l'écran.*
--    ⇒ toute addition d'un `dtype` doit toucher LES TROIS : `psrGetDeviceType` (produit),
--      `psrSetDeviceState` + `applyDeviceToggle` (agissent), `PSR_CONTROLLABLE` (offre le bouton).
local PSR_CONTROLLABLE = { light=true, switch=true, tv=true, radio=true, washer=true, dryer=true, coldunit=true, fridge=true, freezer=true, fridgeFreezer=true, stove=true, appliance=true }

--- Marges du boîtier autour de la dalle (multipliées par l'échelle).
local BEZEL_M = 14   -- gauche / droite / haut
local BEZEL_B = 26   -- bas (sérigraphie)

--- Habille un `ISButton` en touche de terminal : fond sombre, texte ambre, liseré discret.
--- 🔑 ON GARDE DE VRAIS `ISButton` plutôt que du texte cliquable dessiné. Les remplacer par des
---    zones de clic ferait perdre le survol, le focus clavier et le support manette — et
---    surtout, ce sont EUX qui portent les chemins d'action déjà testés (`applyControl`,
---    `onGoToDevice`). **Une refonte visuelle ne doit pas rouvrir un chemin validé.**
local function styleTermButton(btn)
    if not btn then return end
    btn.backgroundColor          = { r = 0.10, g = 0.09, b = 0.06, a = 0.85 }
    btn.backgroundColorMouseOver = { r = 0.32, g = 0.22, b = 0.07, a = 0.95 }
    btn.borderColor              = { r = PHOS.r, g = PHOS.g, b = PHOS.b, a = 0.45 }
    btn.textColor                = { r = PHOS.r, g = PHOS.g, b = PHOS.b, a = 1 }
end

--- Compute current layout dict based on the player's Font Size setting.
--- Multiplies all positions/dimensions by max(1.0, fontH / BASE_FONT_H) so the panel
--- stays readable at any Font Size. Called once at panel construction.
local function computeLayout()
    local fontH = getTextManager():getFontHeight(UIFont.Small)
    local scale = math.max(1.0, fontH / BASE_FONT_H)

    -- 🔴 PLAFOND AJOUTÉ AVEC L'AGRANDISSEMENT (2026-08-07). La base passe de 460 à 760 px, donc
    --    le facteur d'échelle mord beaucoup plus fort : à Font Size 24 (`scale` ≈ 1,71) la
    --    fenêtre atteindrait **1300 × 900** et déborderait d'un écran 1080p. C'est le défaut
    --    exact déjà signalé par un joueur Workshop sur l'ancien panneau — l'agrandissement le
    --    rend simplement plus facile à atteindre.
    -- 📚 Doc lue le 2026-08-07 (`zombie/core/Core.html`) : `getScreenWidth()` et
    --    `getScreenHeight()` existent, `int`, sans paramètre. ⚠️ `getOptionUIFontSize()`
    --    N'EXISTE PAS — c'est bien la hauteur de police mesurée qui doit piloter l'échelle,
    --    et c'est déjà ce que fait la ligne ci-dessus. Rien à changer de ce côté.
    -- 🔑 On plafonne l'ÉCHELLE, pas la largeur finale : rogner la largeur laisserait les colonnes
    --    calculées pour une fenêtre plus large, donc du texte hors cadre. Une seule grandeur
    --    commande la géométrie.
    local core = getCore()
    if core then
        local sw, sh = core:getScreenWidth(), core:getScreenHeight()
        -- Hauteur totale ≈ scale × (20 + 28 + ROWS×BASE_ROW_H + 28 + 34) + 6
        local baseH = 20 + 28 + ROWS_PER_PAGE * BASE_ROW_H + 28 + 34
        if sw and sw > 0 then scale = math.min(scale, (sw * 0.9) / BASE_WIN_W) end
        if sh and sh > 0 then scale = math.min(scale, (sh * 0.9 - 6) / baseH) end
        -- Plancher à 1.0 : les polices PZ ne rétrécissent pas, réduire la mise en page sous la
        -- taille de référence entasserait le texte au lieu de le faire tenir. À la résolution
        -- minimale supportée (1024×768) l'échelle 1 tient largement — vérifié : 760 < 921.
        scale = math.max(1.0, scale)
    end

    return {
        scale     = scale,
        rowH      = math.floor(BASE_ROW_H      * scale),
        winW      = math.floor(BASE_WIN_W      * scale),
        colExpand = math.floor(BASE_COL_EXPAND * scale),
        colType   = math.floor(BASE_COL_TYPE   * scale),
        colCount  = math.floor(BASE_COL_COUNT  * scale),
        colDrain  = math.floor(BASE_COL_DRAIN  * scale),
        colStatus = math.floor(BASE_COL_STATUS * scale),
        colBtn    = math.floor(BASE_COL_BTN    * scale),
        colGo     = math.floor(BASE_COL_GO     * scale),
        colDevBtn = math.floor(BASE_COL_DEVBTN * scale),
    }
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────────────────────────

--- Format a fuel L/h rate as Ah. Shows one decimal only when needed.
--- e.g. 0.002 → "1.6Ah", 0.08 → "64Ah"
local function fmtAh(rate)
    local ah = rate * FUEL_TO_AH
    local rounded = math.floor(ah * 10 + 0.5) / 10
    return string.format("%gAh", rounded)
end

--- Per-panel nominal solar output at full sun (Ah). Mirrors PbSystem:getMaxSolarOutput(1)
--- in PowerBankSystem_Shared.lua (83 * efficiency*1.25/100). Depends only on the
--- client-synced solarPanelEfficiency sandbox, so it's safe to compute client-side here.
--- This answers the recurring player question "how much does each solar panel generate?".
local function perPanelOutput()
    local eff = (SandboxVars.PSR and SandboxVars.PSR.solarPanelEfficiency) or 25
    return 83 * ((eff * 1.25) / 100)
end

--- Build groups from a PowerBank server object (SP / coop-host direct path).
--- Returns array of { dtype, total, activeCount, rate, devices=[{x,y,z,rate,active}] }
--- ⚡ PERF 2026-08-04 : `dl` OPTIONNEL. Après un toggle, `pb:updateDrain()` vient de produire cette
--- liste exacte et de la ranger dans `pb.deviceList` ⇒ la recalculer était un 3ᵉ balayage complet
--- de la structure pour un seul clic (le coût est LINÉAIRE en surface du bâtiment).
--- ✅ Bonus de justesse : la conso facturée et la liste affichée viennent désormais du MÊME relevé.
---@param dl table|nil deviceList déjà résolue
local function buildGroupsFromPB(pb, dl)
    local sq = pb:getSquare()
    if not sq then return {} end
    if not dl then
        local building = sq:getBuilding()
        -- Mirror updateDrain / the server device list: building scan inside a vanilla building,
        -- vanilla-radius scan otherwise (player-built base) — so the Computer lists & manages the
        -- same devices the bank actually powers and drains.
        local drainUnused
        if building then
            drainUnused, dl = pb:getDrainBuilding(sq, building)
        else
            drainUnused, dl = pb:getDrainVanilla(sq)
        end
    end
    if not dl then return {} end

    local groups = {}
    local order  = {}

    for _, dev in ipairs(dl) do
        if not groups[dev.dtype] then
            groups[dev.dtype] = { dtype=dev.dtype, total=0, activeCount=0, rate=0, devices={}, seen={} }
            order[#order + 1] = dev.dtype
        end
        local g   = groups[dev.dtype]
        local sqk = dev.x .. "_" .. dev.y .. "_" .. dev.z
        if not g.seen[sqk] then
            g.seen[sqk]             = true
            g.total                 = g.total + 1
            if dev.active then g.activeCount = g.activeCount + 1 end
            g.devices[#g.devices+1] = { x=dev.x, y=dev.y, z=dev.z, rate=dev.rate, active=dev.active, powered=dev.powered }
        else
            for _, e in ipairs(g.devices) do
                if e.x==dev.x and e.y==dev.y and e.z==dev.z then
                    e.rate = e.rate + dev.rate; break
                end
            end
        end
        if dev.active then g.rate = g.rate + dev.rate end
    end

    local result = {}
    for _, dtype in ipairs(order) do
        local g = groups[dtype]; g.seen = nil
        result[#result + 1] = g
    end
    return result
end

--- Flatten groups + expanded state into ordered row list.
local function buildAllRows(groups, expanded)
    local rows = {}
    for _, grp in ipairs(groups) do
        rows[#rows + 1] = { kind="group", grp=grp }
        if expanded[grp.dtype] then
            for _, dev in ipairs(grp.devices) do
                rows[#rows + 1] = { kind="device", dev=dev, grp=grp }
            end
        end
    end
    return rows
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Constructor
-- ──────────────────────────────────────────────────────────────────────────────

function PSRComputerPanel:new(x, y, width, height)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.title   = getText("IGUI_PSRComputerPanel_Title")
    o:setResizable(false)
    o.L = computeLayout()   -- scaled layout for current Font Size
    o.bx, o.by, o.bz = 0, 0, 0
    o.cx, o.cy, o.cz = nil, nil, nil   -- computer square (proximity check)
    o.player   = 0
    o.devices  = {}   -- array of groups
    o.expanded = {}   -- dtype = true when group row is expanded
    o.page     = 1
    o.allRows  = {}
    o.btnRows  = {}
    o.loaded   = false
    -- Horloges REELLES en millisecondes (voir update()). Les anciens compteurs de FRAMES
    -- (`autoRefreshTimer`, `proximityTimer`, `linkCheckTimer`) sont retires : leur periode variait
    -- du simple au quintuple selon le framerate du joueur.
    local nowNew = getTimestampMs()
    o.autoRefreshAt = nowNew + 10000
    o.proximityAt   = nowNew + 2000
    o.linkCheckAt   = nowNew + 500
    PSRComputerPanel.instance = o
    return o
end

-- ──────────────────────────────────────────────────────────────────────────────
-- createChildren
-- ──────────────────────────────────────────────────────────────────────────────

function PSRComputerPanel:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    local L  = self.L
    local btnH    = math.floor(22 * L.scale)
    local btnW    = math.floor(80 * L.scale)
    local pageBtn = math.floor(28 * L.scale)

    -- Loading label
    self.lblLoading = ISLabel:new(
        L.colType, th + math.floor(28 * L.scale) + 2, 20,
        getText("IGUI_PSRComputerPanel_Loading"),
        1, 0.9, 0.5, 1, UIFont.Small, true
    )
    self.lblLoading:initialise()
    self:addChild(self.lblLoading)

    -- 🔴 LES SIX `ISButton` / `ISLabel` DE COMMANDE ONT ÉTÉ RETIRÉS (2026-08-07, après 2 rendus
    --    en jeu). Habillés en sombre sur la dalle, **aucun n'apparaissait** — ni les `+` de
    --    dépliage, ni les bascules de ligne, ni `Refresh`/`Close`.
    --    ⚠️ **Je n'ai PAS identifié la cause commune avec certitude.** Une piste tenait pour les
    --    deux du bas (créés à `self.height - 28` avec la hauteur de CONSTRUCTION, donc rejetés
    --    hors cadre par le redimensionnement au contenu), mais elle n'explique pas les boutons
    --    de ligne, recréés à chaque `rebuildView` à des coordonnées justes.
    -- 🔑 D'où le choix : **supprimer la dépendance plutôt que continuer à deviner.** Les
    --    commandes deviennent du TEXTE entre crochets + zones de clic — c'est exactement la
    --    maquette validée par le Commandeur, et ça élimine toute la classe de problème.
    -- 📌 Et je corrige mon propre argument d'il y a deux tours (« remplacer les boutons
    --    rouvrirait un chemin testé ») : **c'était faux**. Le chemin testé, ce sont
    --    `applyControl` et `onGoToDevice` ; le dispatch qui les appelle n'en fait pas partie.
    --    Même erreur qu'hier : une garde posée sur la MÉCANIQUE au lieu de la CIBLE.
    --    On ne perd que le survol et le focus manette, que la maquette acceptait déjà.
    if self.lblLoading then self.lblLoading.r, self.lblLoading.g, self.lblLoading.b = PHOS.r, PHOS.g, PHOS.b end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Zones cliquables — remplacent les ISButton retirés
-- ──────────────────────────────────────────────────────────────────────────────
-- Reconstruites à chaque rendu, comme dans la maquette. Le dispatch appelle les MÊMES
-- fonctions d'action qu'avant : rien du chemin serveur ne change.
function PSRComputerPanel:zone(x, y, w, h, fn)
    self.zones[#self.zones + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

function PSRComputerPanel:onMouseDown(x, y)
    for _, z in ipairs(self.zones or {}) do
        if x >= z.x and x <= z.x + z.w and y >= z.y and y <= z.y + z.h then
            z.fn(self); return true
        end
    end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end

--- Dessine un libellé « [ texte ] » et enregistre sa zone. `dim` = commande indisponible.
function PSRComputerPanel:ctl(text, x, y, fn, dim)
    local label = "[ " .. text .. " ]"
    local w  = getTextManager():MeasureStringX(UIFont.Small, label)
    local fh = getTextManager():getFontHeight(UIFont.Small)
    self:drawText(label, x, y, PHOS.r, PHOS.g, PHOS.b, dim and 0.3 or 0.85, UIFont.Small)
    if fn and not dim then self:zone(x - 2, y - 2, w + 4, fh + 4, fn) end
    return w
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Data fetch (dual path: SP/host direct, dedicated MP via network)
-- ──────────────────────────────────────────────────────────────────────────────

--- Y de la PREMIÈRE ligne de données.
--- 🔴 CRÉÉE APRÈS LE 1ᵉʳ RENDU EN JEU (2026-08-07) : l'en-tête « PSR TERMINAL » recouvrait la
---    ligne de colonnes. Le rendu ET la création des boutons calculaient chacun leur origine,
---    l'un depuis la dalle, l'autre depuis `th + headerY` — deux repères pour une même grille.
--- 🔑 **Une grille n'a qu'une origine.** Elle vit ici, et les deux appelants la lisent ; c'est la
---    seule forme qui ne peut pas se désynchroniser au prochain ajustement de marge.
function PSRComputerPanel:tableTop()
    local L  = self.L
    local fh = getTextManager():getFontHeight(UIFont.Small)
    return self:titleBarHeight()
         + math.floor(BEZEL_M * L.scale)          -- marge haute du boîtier
         + math.floor(6 * L.scale) + fh           -- en-tête « PSR TERMINAL »
         + math.floor(10 * L.scale)               -- filet
         + getTextManager():getFontHeight(UIFont.Large)
         + math.floor(12 * L.scale)               -- bandeau RÉSEAU + filet
         + fh + math.floor(6 * L.scale)           -- ligne d'en-tête des colonnes
end

--- Relit la bank et agrège le réseau pour le bandeau du haut.
--- 🔴 CADENCÉ À 1 s RÉELLE, JAMAIS PAR FRAME. `getLinkedBanksPanelInfo` est un BFS sur tout le
---    réseau de banks : l'appeler au rendu coûterait un parcours complet par image, et le coût
---    croît avec le nombre de banks liées. C'est le défaut exact corrigé le 04/08 sur le scan de
---    générateurs de la vue Details — on ne le rejoue pas de l'autre côté.
--- 🔑 Horloge en millisecondes et non compteur de frames : un compteur voit sa période varier
---    du simple au quintuple selon le framerate du joueur.
function PSRComputerPanel:refreshNetworkStats()
    self.netReadAt = getTimestampMs() + 1000
    self.netOK = false
    if not (self.bx and PSR.PBSystem_Client) then return end

    -- Même résolution que `PSRStatusWindow.OnOpenPanel` : d'abord l'objet Lua connu, sinon on en
    -- reconstruit un depuis la modData de l'IsoObject. ⚠️ Ce second chemin est celui qui rend la
    -- lecture VALABLE EN DÉDIÉ : elle passe par la modData répliquée, jamais par `PBSystem_Server`.
    local pb = PSR.PBSystem_Client:getLuaObjectAt(self.bx, self.by, self.bz)
    if not pb then
        local sq = getSquare(self.bx, self.by, self.bz)
        local iso = sq and PSR.PBSystem_Client:getIsoObjectOnSquare(sq)
        if iso then
            local PowerBank = require("PSR/Powerbank/PowerBankObject_Client")
            pb = { x = self.bx, y = self.by, z = self.bz, luaSystem = PSR.PBSystem_Client }
            setmetatable(pb, PowerBank)
        end
    end
    if not pb then return end
    pb:updateFromIsoObject()

    local _nPanels, links, nCharge, _nDrain, nCapacity = PSR.WorldUtil.getLinkedBanksPanelInfo(pb)
    local linked = links and #links > 0
    -- Sur un réseau lié on montre les totaux RÉSEAU ; seule la bank ouverte sinon. Mélanger les
    -- deux portées dans un même ratio est l'erreur qui a faussé les estimations de recharge.
    self.netCharge   = linked and (nCharge or 0)   or (pb.charge or 0)
    self.netCapacity = linked and (nCapacity or 0) or (pb.maxcapacity or 0)
    self.netDrain    = pb.drain or 0
    self.netLinked   = linked
    self.netOK       = true
end

-- 🗑️ `layoutFooter()` RETIRÉE ici : elle repositionnait les commandes fixes quand la fenêtre se
--    redimensionnait au contenu. Les deux raisons de son existence ont disparu le même jour —
--    les `ISButton` ont laissé place à du texte dessiné, et la hauteur est redevenue fixe.
--    Ses cinq gardes `if self.btnX then` la rendaient inoffensive, donc invisible : c'est
--    exactement le code mort qui survit des mois et que la lecture suivante prend pour actif.

function PSRComputerPanel:fetchDeviceList()
    local srv = PSR.PBSystem_Server
    if srv then
        local pb = srv:getLuaObjectAt(self.bx, self.by, self.bz)
        if not pb then self:populateDevices({}); return end
        -- 🏘️ `D-11` (2026-08-21) : le terminal liste désormais TOUT LE RÉSEAU, pas sa seule bank.
        --    `getNetworkDeviceList` réutilise les `deviceList` déjà calculées (pas de re-balayage).
        self:populateDevices(buildGroupsFromPB(pb, srv:getNetworkDeviceList(pb)))
    else
        local char = getSpecificPlayer(self.player)
        if char then
            sendClientCommand(char, "psr_powerbank", "requestDeviceList",
                { x=self.bx, y=self.by, z=self.bz,
                  computer={ x=self.cx, y=self.cy, z=self.cz } })
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- populateDevices — store data then rebuild from page 1
-- ──────────────────────────────────────────────────────────────────────────────

function PSRComputerPanel:clearRows()
    for _, btn in ipairs(self.btnRows) do self:removeChild(btn) end
    self.btnRows = {}
end

--- `R-32` (2026-08-23) : DRAIN FACTURE DU RESEAU, recalcule depuis les groupes AFFICHES.
--- 💥 Le defaut : l'en-tete montrait `pb.drain`, c'est-a-dire la bank DU TERMINAL OUVERT,
---    pendant que le tableau juste dessous liste tout le RESEAU. Mesure sur deux terminaux du
---    meme reseau, banks a UNE case l'une de l'autre : **156,8 Ah** et **332,8 Ah**, memes
---    appareils. Le meme reseau annoncait deux valeurs selon le terminal ouvert.
--- ⚙️ On somme ce que le panneau MONTRE DEJA -- meme regle que la facturation serveur
---    (`active and powered`), meme conversion (`FUEL_TO_AH`). Aucun champ replique en plus,
---    aucun changement de format de modData : le calcul vit entierement dans l'affichage.
--- ⚠️ `powered` a du etre AJOUTE aux DEUX constructeurs d'entrees de groupe le meme jour
---    (ici `:175` et `PowerBankSystem_Commands:211`, le chemin DEDIE). En rater un rendrait
---    `powered` nil sur ce chemin et l'en-tete afficherait **0**.
function PSRComputerPanel:computeBilledDrain()
    local total = 0
    for _, grp in ipairs(self.devices or {}) do
        for _, dv in ipairs(grp.devices or {}) do
            if dv.active and dv.powered then total = total + (dv.rate or 0) end
        end
    end
    self.netBilled = total * FUEL_TO_AH
end

-- Initial load: reset to page 1 (called by fetchDeviceList / OnOpen).
function PSRComputerPanel:populateDevices(devices)
    self.devices = devices
    self:computeBilledDrain()
    self.loaded  = true
    self.page    = 1
    self.lblLoading:setVisible(false)
    self:rebuildView()
end

-- Control refresh: preserve current page (called after Disable / Enable action).
function PSRComputerPanel:refreshDevices(devices)
    self.devices = devices
    self:computeBilledDrain()
    self.loaded  = true
    self.lblLoading:setVisible(false)
    self:rebuildView()  -- page unchanged
end

-- ──────────────────────────────────────────────────────────────────────────────
-- rebuildView — recreate buttons for the current page
-- ──────────────────────────────────────────────────────────────────────────────

function PSRComputerPanel:rebuildView()
    self:clearRows()
    local L       = self.L
    local expW    = math.floor(18 * L.scale)
    local goW     = math.floor(28 * L.scale)
    local allRows = buildAllRows(self.devices, self.expanded)
    self.allRows  = allRows
    local total   = #allRows
    local pages   = math.max(1, math.ceil(total / ROWS_PER_PAGE))
    self.page     = math.min(self.page, pages)
    local p0      = (self.page - 1) * ROWS_PER_PAGE + 1
    local p1      = math.min(total, p0 + ROWS_PER_PAGE - 1)

    -- 🔴 HAUTEUR FIXE — correction d'une décision à moi (Commandeur, 2026-08-07).
    --    J'avais dimensionné la fenêtre sur les lignes RÉELLEMENT affichées, pour supprimer un
    --    écran à moitié vide. Résultat : déplier un groupe faisait grandir le moniteur.
    -- 🔑 **Un écran d'ordinateur n'a pas de taille variable.** Je traitais un défaut visuel en
    --    cassant la métaphore que toute la refonte sert à établir — et le débordement avait déjà
    --    sa réponse : LA PAGINATION. Un écran partiellement vide se lit comme un écran ; un écran
    --    qui change de taille se lit comme un bug.
    -- 📌 La hauteur ne dépend donc QUE de `ROWS_PER_PAGE` : constante d'une ouverture à l'autre,
    --    quel que soit le contenu, avec l'espace de pagination toujours réservé.
    local footer = math.floor(28 * L.scale) + math.floor(26 * L.scale)
                 + math.floor(BEZEL_B * L.scale)
    local fixedH = self:tableTop() + ROWS_PER_PAGE * L.rowH + math.floor(10 * L.scale) + footer
    if math.abs((self.height or 0) - fixedH) > 2 then
        self:setHeight(fixedH)
    end
    self.pages = pages
    -- 🔑 `rebuildView` ne crée plus AUCUN enfant : elle calcule les lignes et la hauteur, un
    --    point c'est tout. Les commandes sont dessinées et enregistrées dans `render()`, où
    --    elles ne peuvent plus se désynchroniser des lignes qu'elles pilotent.
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Callbacks
-- ──────────────────────────────────────────────────────────────────────────────

function PSRComputerPanel:onExpandToggle(btn)
    local dtype = btn.PSR_dtype
    self.expanded[dtype] = not self.expanded[dtype] and true or nil
    self.page = 1
    self:rebuildView()
end

function PSRComputerPanel:onToggleGroup(btn)
    self:applyControl(btn.PSR_dtype, nil, nil, nil, btn.PSR_on)
end

function PSRComputerPanel:onToggleDevice(btn)
    self:applyControl(btn.PSR_dtype, btn.PSR_x, btn.PSR_y, btn.PSR_z, btn.PSR_on)
end

-- Signature passée de `(btn)` à `(x, y, z)` : les coordonnées ne transitent plus par des champs
-- posés sur un bouton. **Le corps n'a pas changé** — c'est le chemin d'action testé, on ne le
-- rouvre pas, on change seulement qui l'appelle.
function PSRComputerPanel:goToSquare(gx, gy, gz)
    local chr = getSpecificPlayer(self.player)
    if not chr then return end
    local sq = getSquare(gx, gy, gz)
    if not sq then return end
    -- Use AdjacentFreeTileFinder (vanilla ISBBQMenu pattern) to find the nearest
    -- accessible square next to the device — the device square itself may be blocked
    -- (lamp in wall, appliance, furniture). Falls back to exact square if none found.
    local dest = AdjacentFreeTileFinder.Find(sq, chr)
    if dest then
        ISTimedActionQueue.add(ISWalkToTimedAction:new(chr, dest))
    else
        ISTimedActionQueue.add(ISPathFindAction:pathToLocationF(chr, sq:getX(), sq:getY(), sq:getZ()))
    end
end

--- Toggle wall switches using ISToggleLightAction (exact vanilla path).
--- Using the TimedAction framework captures any Java-level cascade that
--- direct toggle() from plain Lua context misses (start→faceThisObject, perform→complete).
--- Guard: only queue if current state ≠ desired state.
local function clientToggleSwitches(chr, devices, x, y, z, on)
    local function tryToggle(sx, sy, sz)
        local sq = getSquare(sx, sy, sz)
        if not sq then return end
        local objs = sq:getObjects()
        for i = 0, objs:size() - 1 do
            local obj = objs:get(i)
            if instanceof(obj, "IsoLightSwitch") and obj:isActivated() ~= on then
                ISTimedActionQueue.add(ISToggleLightAction:new(chr, obj))
            end
        end
    end
    if x then
        tryToggle(x, y, z)
    else
        -- Group: iterate cached device list for dtype="switch"
        for _, grp in ipairs(devices) do
            if grp.dtype == "switch" then
                for _, dev in ipairs(grp.devices) do
                    tryToggle(dev.x, dev.y, dev.z)
                end
            end
        end
    end
end

--- ⚡ Le réseau de cette bank fournit-il du courant ? (2026-08-13)
--- 🔑 UNE SEULE fonction pour les TROIS contextes — c'est tout l'enjeu :
---    · solo / hôte coop -> `PSR.PBSystem_Server` est présent, on lit en direct
---    · client de dédié  -> il est NIL ; on lit la valeur reçue avec `deviceList`
--- ⚠️ Écrire cette garde en ne lisant que `srv` la rendrait INERTE en dédié — la
---    régression exacte de la v1.67 (correctif toxique côté serveur, inerte pour `Kirthas`).
--- ⚖️ `nil` = « je ne sais pas » et vaut AUTORISÉ : mieux vaut laisser passer une action
---    que verrouiller le terminal d'un joueur sur une information qu'on n'a pas reçue.
---@return boolean
function PSRComputerPanel:networkSupplies()
    local srv = PSR.PBSystem_Server
    if srv then
        local pb = srv:getLuaObjectAt(self.bx, self.by, self.bz)
        if not pb then return true end                  -- bank introuvable : on ne bloque pas
        return srv:networkSupplies(pb) and true or false
    end
    if self.netSupplies == nil then return true end     -- pas encore reçu : on ne bloque pas
    return self.netSupplies and true or false
end

--- Une bank du réseau de ce terminal est-elle ALLUMÉE ? — critère de la garde v1.71.
--- ⚖️ **Trois états, et le `nil` vaut AUTORISÉ** : `networkAnyBankOn` rend `nil` quand un maillon
---    lié n'a pas pu être résolu, et le message réseau peut ne pas être encore arrivé. Dans les
---    deux cas on **ne bloque pas** — bloquer sur un inconnu est exactement le défaut de la v1.68,
---    et ici l'erreur permissive ne coûte qu'un clic sans effet, l'erreur restrictive enferme le
---    joueur hors de son matériel.
--- 📡 Solo / hôte coop : lecture directe. Client de dédié : valeur reçue avec `deviceList`.
---@return boolean true = on autorise · false = TOUTES les banks du réseau sont éteintes, prouvé
function PSRComputerPanel:networkAnyBankOn()
    local srv = PSR.PBSystem_Server
    if srv and srv.networkAnyBankOn then
        local pb = srv:getLuaObjectAt(self.bx, self.by, self.bz)
        if not pb then return true end                  -- bank introuvable : on ne bloque pas
        local r = srv:networkAnyBankOn(pb)
        if r == nil then return true end                -- inconnu : on ne bloque pas
        return r and true or false
    end
    if self.netAnyOn == nil then return true end        -- pas encore reçu / inconnu : on ne bloque pas
    return self.netAnyOn and true or false
end

--- Send control command to the server (group or individual device).
--- x/y/z nil = group command; x/y/z set = individual device command.
function PSRComputerPanel:applyControl(dtype, x, y, z, on)
    -- ⚡ GARDE UNIQUE — « pas de bank qui fournit = pas de courant PSR » (Commandeur, 13/08).
    -- 🔑 Elle est ICI et nulle part ailleurs : `applyControl` est le SEUL point par lequel
    --    passent tous les toggles du terminal (groupe et appareil isolé, solo/coop et dédié).
    --    Un filtre posé dans une branche `dtype` aurait fui par toutes les autres — et c'est
    --    exactement le défaut observé : `light` n'a jamais vérifié l'alimentation.
    -- ⚖️ On ne bloque QUE l'allumage. Éteindre reste toujours permis : refuser d'éteindre
    --    enfermerait le joueur avec des appareils allumés qu'il ne pourrait plus couper.
    -- 🔌 GARDE DU TERMINAL — v1.71, elle REMPLACE celle de la v1.68 (retirée le matin du 14/08).
    --
    -- 🎯 **Le critère a changé, et c'est tout le sujet.** v1.68 demandait *« quelque chose
    --    fournit-il du courant ? »* — une **inférence tirée d'une absence**, d'où quatre
    --    régressions. On demande désormais *« une bank de ce réseau est-elle ALLUMÉE ? »* — un
    --    **fait positif, décidé par le joueur** (directive Commandeur, 2026-08-14).
    --
    -- 🔗 **Le RÉSEAU, pas la bank du terminal** — question du Commandeur : *« et dans le cas où il
    --    y a une bank liée ? »*. Un terminal collé à une bank éteinte dont un jumeau lié tourne
    --    doit rester utilisable. `networkAnyBankOn` fait le BFS et, contrairement à `getNetwork`,
    --    **signale un maillon non résolu** au lieu de le perdre en silence.
    --
    -- 🕳️ **`nil` (inconnu) vaut AUTORISÉ.** Bloquer sur un inconnu est le défaut de la v1.68.
    --    L'asymétrie décide : une permission de trop coûte un clic sans effet, un refus de trop
    --    **enferme le joueur hors de son matériel**.
    --
    -- ⚖️ **On ne bloque QUE l'allumage** — éteindre reste toujours permis.
    --
    -- 🔴 **Ce que ça règle pour `Heckerpecker`** (*« I can't turn the freezer on even though I have
    --    a generator »*) : sa bank **allumée mais ne fournissant pas** ne bloque plus rien — c'est
    --    exactement le cas qu'il a signalé. ⚠️ **Ce que ça NE règle pas, et c'est assumé** : bank
    --    **éteinte** + alimentation par générateur tiers ⇒ le terminal reste bloqué. C'est
    --    cohérent — *le Solar Computer tourne sur la bank* — mais ce n'est pas gratuit : à
    --    rouvrir si un joueur le signale avec cette configuration précise.
    --
    -- 🌍 **Texte** : on réutilise `IGUI_PSR_NoBankSupplying` (*« No battery bank is supplying
    --    power. »*), **vraie chaque fois qu'elle s'affiche** puisqu'on ne bloque que si TOUTES les
    --    banks sont éteintes. ⏭️ Une formulation plus actionnable (*« This battery bank is switched
    --    off »*) coûte une clé neuve dans **28 locales** ⇒ à faire avec la prochaine passe i18n,
    --    pas le jour d'une publication. 📅 Dette ouverte le 2026-08-14.
    -- 🔴🔴 EXEMPTION AJOUTÉE LE 2026-08-16 — LA GARDE ENFERMAIT LE JOUEUR AVEC SA NOURRITURE.
    --
    -- 🚩 **Le déclencheur de réouverture qu'on avait nous-mêmes écrit ci-dessus a sauté.** La note
    --    du 14/08 disait : *« bank éteinte + alimentation par générateur tiers ⇒ le terminal reste
    --    bloqué […] à rouvrir si un joueur le signale avec cette configuration précise »*.
    --    `real_maurice`, le 15/08 : *« my fridges and freezers […] labelled as off despite having
    --    my generator hooked up and the battery bank turned off »*. Configuration exacte.
    --
    -- 💥 CE QUE ÇA FAISAIT, et c'est une BOUCLE FERMÉE, pas une gêne :
    --   · un frigo laissé `_off` par la coupe automatique de la v1.68 porte un état **gravé dans
    --     la save** — il ne se relève pas tout seul ;
    --   · la migration `restoreColdDevices` est un one-shot **déjà consommé** chez lui ;
    --   · et cette garde refusait le seul geste manuel qui restait.
    --   ⇒ **aucune sortie en jeu.** Ni automatique, ni manuelle.
    --
    -- ⚖️ L'ASYMÉTRIE QUI TRANCHE, et c'est exactement celle qui a justifié la garde elle-même :
    --    on ne bloque que l'allumage *parce qu'interdire d'éteindre enfermerait le joueur*.
    --    Interdire de **rallumer un état persistant** l'enferme de la même façon, en pire — ça se
    --    paie en nourriture, pas en clic. 📚 Et le gain du refus est **nul** : le moteur gate déjà
    --    le froid sur l'alimentation (`ItemContainer.getTemprature` → `isPowered()`, bytecode
    --    42.20). Rallumer un frigo non alimenté ne refroidit rien ; ça lui rend son icône, son
    --    titre et sa place dans la liste de consommation.
    --
    -- 📌 `PSR.PERSISTENT_OFF` est le point unique (`shared/PSR/Utilities.lua`) — à ne pas confondre
    --    avec `coolingType` ci-dessous, qui répond à une AUTRE question (« faut-il rediffuser le
    --    `setType` ? ») et exclut `coldunit` à juste titre, celui-ci passant par `modData`.
    if on and not PSR.PERSISTENT_OFF[dtype] and not self:networkAnyBankOn() then
        local chr = getSpecificPlayer(self.player)
        if chr then chr:Say(getText("IGUI_PSR_NoBankSupplying")) end
        return
    end
    local srv = PSR.PBSystem_Server
    -- Fridges/freezers toggle via container:setType, which does NOT auto-replicate over the network.
    local coolingType = (dtype == "fridge" or dtype == "freezer" or dtype == "fridgeFreezer")
    if srv then
        -- SP / coop-host: direct server access (instant UI refresh — no command round-trip).
        -- Wall switches: ISToggleLightAction works here (same process, adjacency is fine).
        if dtype == "switch" then
            local chr = getSpecificPlayer(self.player)
            if chr then clientToggleSwitches(chr, self.devices, x, y, z, on) end
        end
        local pb = srv:getLuaObjectAt(self.bx, self.by, self.bz)
        if pb then
            if x then
                pb:controlDevice(x, y, z, dtype, on)
            else
                -- 🔴 `D-11` (2026-08-21) — ON PASSE DÉSORMAIS LES COORDS DU RÉSEAU.
                -- 💥 Sans elles, `controlDeviceGroup` retombait sur son repli, qui rebalaie **sa
                --    seule bank** : le joueur voyait 4 TV, en éteignait 1, et les 3 portées par la
                --    bank LIÉE ne bougeaient pas. *Un demi-effet, sans message, sans erreur.*
                -- 🔑 Ce chemin-ci est celui du SOLO et de l'HÔTE COOP — le dédié passe par
                --    `Commands`. Les deux appellent maintenant le même helper partagé.
                pb:controlDeviceGroup(dtype, on, srv:getNetworkDeviceCoords(pb, dtype))
            end
            -- 🔄 `D-11` : TOUT le réseau se recalcule, pas seulement la bank du terminal — sinon
            --    les banks liées renvoient un `active` périmé et l'écran contredit une action
            --    qui a pourtant réussi (« le statut ne se rafraîchit pas », mesuré en jeu).
            srv:refreshNetworkDrain(pb)
            pb:saveData(true)
            -- Refresh UI immediately, preserving current page.
            -- ⚡ PERF : `updateDrain()` vient de rafraîchir `pb.deviceList` (3ᵉ scan supprimé).
            -- 🏘️ `D-11` : on agrège ensuite le RÉSEAU — les autres banks gardent leur liste déjà
            --    calculée, donc le coût supplémentaire est une simple concaténation.
            --    ⚠️ Sans ça, un toggle rétrécissait l'affichage à la seule bank du terminal :
            --    la liste complète à l'ouverture, tronquée au premier clic. *Un défaut qui
            --    n'apparaît qu'APRÈS une action est le plus difficile à rapporter.*
            local srvNet = PSR.PBSystem_Server
            self:refreshDevices(buildGroupsFromPB(pb,
                srvNet and srvNet:getNetworkDeviceList(pb) or pb.deviceList))
            -- Fridges/freezers swap container type via setType, which does NOT auto-replicate.
            -- On a coop HOST, broadcast the swap so remote clients apply it too (the host already
            -- applied it directly above; setType is idempotent → the host receiving it is a no-op).
            if coolingType and isServer() then
                local devices
                if x then
                    devices = { { x = x, y = y, z = z } }
                else
                    devices = {}
                    for _, d in ipairs(pb.deviceList or {}) do
                        if d.dtype == dtype then devices[#devices + 1] = { x = d.x, y = d.y, z = d.z } end
                    end
                end
                if #devices > 0 then
                    sendServerCommand("PSR", "applyDeviceToggle", { dtype = dtype, on = on, devices = devices })
                end
            end
        end
    else
        -- Dedicated MP: send to server; visual toggle arrives via applyDeviceToggle.
        -- Wall switches in dedicated: ISToggleLightAction fails (adjacency check);
        -- server sends applyDeviceToggle → client calls obj:toggle() directly.
        local char = getSpecificPlayer(self.player)
        if char then
            if x then
                sendClientCommand(char, "psr_powerbank", "controlDevice", {
                    bank = { x=self.bx, y=self.by, z=self.bz },
                    computer = { x=self.cx, y=self.cy, z=self.cz },
                    dtype=dtype, x=x, y=y, z=z, on=on,
                })
            else
                sendClientCommand(char, "psr_powerbank", "controlDeviceGroup", {
                    bank = { x=self.bx, y=self.by, z=self.bz },
                    computer = { x=self.cx, y=self.cy, z=self.cz },
                    dtype=dtype, on=on,
                })
            end
            -- Server will send back updated deviceList via OnServerCommand
        end
    end
end

function PSRComputerPanel:onPrevPage()
    if self.page > 1 then self.page = self.page - 1; self:rebuildView() end
end

function PSRComputerPanel:onNextPage()
    local pages = math.max(1, math.ceil(#self.allRows / ROWS_PER_PAGE))
    if self.page < pages then self.page = self.page + 1; self:rebuildView() end
end

function PSRComputerPanel:onRefresh()
    self.loaded   = false
    self.expanded = {}
    self.page     = 1
    if self.lblLoading then self.lblLoading:setVisible(true) end
    -- 🔴 Ces trois lignes appelaient `self.btnPrev/btnNext/lblPage:setVisible(false)` sur des
    --    enfants SUPPRIMÉS avec le passage aux commandes dessinées ⇒ appel de méthode sur `nil`,
    --    donc **erreur Lua au premier clic sur « refresh »**. Trouvé par un balayage des
    --    références aux symboles retirés, pas à la relecture.
    -- 📌 Forme : *supprimer un objet ne supprime pas ses appelants* — et ceux-ci vivent souvent
    --    loin du site de suppression. Après tout retrait, balayer le fichier par le NOM retiré.
    self.zones = {}
    self.pages = 1
    self:fetchDeviceList()
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Auto-refresh (~10 s — preserves page and expanded groups)
-- ──────────────────────────────────────────────────────────────────────────────

function PSRComputerPanel:update()
    ISCollapsableWindow.update(self)

    -- Proximity check: close panel if player moves more than 5 tiles from the computer.
    -- Checked every ~2 s (60 frames) to keep per-frame cost negligible.
    -- Même conversion que l'auto-refresh ci-dessous : ces compteurs étaient en FRAMES, donc leur
    -- période réelle variait du simple au quintuple selon le framerate. Le travail par tick est ici
    -- négligeable, mais on balaye la famille plutôt que le seul cas coûteux — c'est exactement le
    -- défaut « corrigé à un endroit, pas à son jumeau » que cet audit a mis en évidence.
    if self.cx then
        local nowP = getTimestampMs()
        self.proximityAt = self.proximityAt or (nowP + 2000)
        if nowP >= self.proximityAt then
            self.proximityAt = nowP + 2000   -- 2 s réelles
            local pchr = getSpecificPlayer(self.player)
            if pchr then
                local psq = pchr:getSquare()
                if psq then
                    local dx = psq:getX() - self.cx
                    local dy = psq:getY() - self.cy
                    if dx * dx + dy * dy > 4 then   -- ~2-tile radius (RP: must stay at the computer)
                        self:close()
                        return
                    end
                end
            end

        end
    end

    -- La fenêtre doit se fermer quand le lien qu'elle pilote n'existe plus (signal Commandeur,
    -- 2026-08-04 : délier l'ordinateur laissait le panneau ouvert sur une liaison morte, et
    -- manipulable). Couvre TOUS les chemins de déliaison — depuis l'ordinateur, depuis la bank,
    -- ou par un autre joueur en MP : une fenêtre ne doit pas dépendre de qui l'a invalidée pour
    -- savoir qu'elle l'est.
    --
    -- ⏱️ Timer PROPRE, à ~0,5 s, et volontairement plus court que celui de la proximité (~2 s) :
    -- à 2 s la fermeture se voyait « en retard » et le Commandeur a signalé, à raison, que ça
    -- ferait une question de joueur. Une FAQ sert à expliquer un comportement IRRÉDUCTIBLE —
    -- celui-ci était réductible, donc on le supprime au lieu de le documenter. Le coût est nul :
    -- une case porte une poignée d'objets, deux passages par seconde ne se mesurent pas.
    -- On ne ferme toujours PAS au clic : la déliaison est une TimedAction interruptible, fermer
    -- au clic fermerait sur une intention et non sur un fait.
    if self.bx and self.cx then
        local nowL = getTimestampMs()
        self.linkCheckAt = self.linkCheckAt or (nowL + 500)
        if nowL >= self.linkCheckAt then
            self.linkCheckAt = nowL + 500   -- 0,5 s réelles (était 15 frames : 0,1 s à 144 fps)
            local csq = getSquare(self.cx, self.cy, self.cz)
            -- ⚠️ Case non chargée = on NE SAIT PAS : on ne ferme rien sur une absence d'info.
            if csq then
                local stillLinked = false
                local objs = csq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)
                    local lb = obj and obj:getModData().PSR_linkedBank
                    if lb and lb.x == self.bx and lb.y == self.by and lb.z == self.bz then
                        stillLinked = true
                        break
                    end
                end
                if not stillLinked then
                    self:close()
                    return
                end
            end
        end
    end

    -- Bandeau réseau : relecture à 1 s réelle. Indépendante de `loaded`, parce que le bandeau
    -- s'affiche même pendant le chargement de la liste d'appareils.
    local nowNet = getTimestampMs()
    self.netReadAt = self.netReadAt or 0
    if nowNet >= self.netReadAt then self:refreshNetworkStats() end

    if not self.loaded then return end
    -- 🔴 COMPTEUR DE FRAMES → HORLOGE REELLE (audit 2026-08-04).
    -- Valait `self.autoRefreshTimer + 1` avec un seuil a 300 et le commentaire « ~10 s at 30 fps ».
    -- `update()` est appele UNE FOIS PAR FRAME : a 144 fps la periode reelle tombait a **~2 s**,
    -- soit **5x plus** de scans complets du batiment — et, en dedie, 5x plus d'aller-retours reseau,
    -- avec une charge serveur proportionnelle. *Plus le joueur avait de FPS, plus il coutait cher.*
    -- C'est le motif exact de l'incident PFR v1.21 : un travail lourd cadence par l'affichage.
    local now = getTimestampMs()
    self.autoRefreshAt = self.autoRefreshAt or (now + 10000)
    if now >= self.autoRefreshAt then
        self.autoRefreshAt = now + 10000   -- 10 s REELLES, quel que soit le framerate
        self:silentFetch()
    end
end

-- Refresh without resetting page or expanded groups (used by auto-refresh and OnServerCommand).
function PSRComputerPanel:silentFetch()
    local srv = PSR.PBSystem_Server
    if srv then
        local pb = srv:getLuaObjectAt(self.bx, self.by, self.bz)
        -- 🏘️ `D-11` : le rafraîchissement automatique doit voir le MÊME périmètre que l'ouverture.
        --    ⚠️ Le laisser sur une seule bank aurait fait « clignoter » la liste : complète à
        --    l'ouverture, réduite au 1ᵉʳ rafraîchissement automatique — et c'est le genre de défaut
        --    qu'un joueur décrit comme « ça disparaît tout seul », donc impossible à reproduire.
        if pb then self:refreshDevices(buildGroupsFromPB(pb, srv:getNetworkDeviceList(pb))) end
    else
        -- Dedicated MP: send request; response arrives via OnServerCommand → refreshDevices
        local char = getSpecificPlayer(self.player)
        if char then
            sendClientCommand(char, "psr_powerbank", "requestDeviceList",
                { x=self.bx, y=self.by, z=self.bz,
                  computer={ x=self.cx, y=self.cy, z=self.cz } })
        end
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- render
-- ──────────────────────────────────────────────────────────────────────────────

--- Texte à halo : 4 passes faibles SYMÉTRIQUES + la passe nette.
--- ⚠️ Coût ×5 par chaîne ⇒ réservé à l'en-tête et aux gros chiffres, JAMAIS au tableau
---    (16 lignes × 4 colonnes = 64 chaînes ⇒ 320 appels de rendu par frame).
--- 🔑 Décalage symétrique et non directionnel : un halo d'un seul côté se lit comme une ombre
---    portée, pas comme du phosphore qui rayonne.
function PSRComputerPanel:glow(text, x, y, c, font)
    self:drawText(text, x - 1, y, c.r, c.g, c.b, 0.22, font)
    self:drawText(text, x + 1, y, c.r, c.g, c.b, 0.22, font)
    self:drawText(text, x, y - 1, c.r, c.g, c.b, 0.22, font)
    self:drawText(text, x, y + 1, c.r, c.g, c.b, 0.22, font)
    self:drawText(text, x, y,     c.r, c.g, c.b, 1,    font)
    return getTextManager():MeasureStringX(font, text)
end

function PSRComputerPanel:render()
    ISCollapsableWindow.render(self)
    self.zones = {}

    local th = self:titleBarHeight()
    local L  = self.L
    local W, H = self.width, self.height

    -- ── Boîtier + dalle ────────────────────────────────────────────────────────────────────
    -- 📌 DIVERGENCE ASSUMÉE AVEC LA MAQUETTE : la barre de titre vanilla reste. On la garde
    --    parce qu'`ISCollapsableWindow` apporte le déplacement, le repli et l'enregistrement
    --    `ISLayoutManager` — trois comportements testés qu'une refonte visuelle ne justifie pas
    --    de réécrire. Le moniteur est donc dessiné SOUS elle. À juger en jeu.
    local bx, by = 0, th
    local bw, bh = W, H - th
    self:drawRect(bx, by, bw, bh / 2, 1, BZ_TOP.r, BZ_TOP.g, BZ_TOP.b)
    self:drawRect(bx, by + bh / 2, bw, bh / 2, 1, BZ_BOT.r, BZ_BOT.g, BZ_BOT.b)

    local mx = math.floor(14 * L.scale)
    local mb = math.floor(26 * L.scale)
    local sx, sy = bx + mx, by + mx
    local sw, sh = bw - mx * 2, bh - mx - mb
    self:drawRect(sx, sy, sw, sh, 1, SCRBG.r, SCRBG.g, SCRBG.b)
    self:drawRectBorder(sx, sy, sw, sh, 1, 0.08, 0.08, 0.06)

    -- Sérigraphie du boîtier
    local brand = "PLYSKEN SOLAR REVOLUTION"
    local bwid = getTextManager():MeasureStringX(UIFont.NewSmall, brand)
    self:drawText(brand, (W - bwid) / 2, by + bh - mb + math.floor(6 * L.scale),
                  0.43, 0.40, 0.36, 1, UIFont.NewSmall)

    if not self.loaded then return end

    local allRows = self.allRows
    local p0      = (self.page - 1) * ROWS_PER_PAGE + 1
    local p1      = math.min(#allRows, p0 + ROWS_PER_PAGE - 1)

    -- ── En-tête du terminal ────────────────────────────────────────────────────────────────
    local cx  = sx + math.floor(12 * L.scale)
    local cw  = sw - math.floor(24 * L.scale)
    local hy  = sy + math.floor(6 * L.scale)
    self:glow("PSR TERMINAL", cx, hy, PHOS_HI, UIFont.Small)
    -- 📌 Pas de numéro de version affiché, contrairement à la maquette : une chaîne de version en
    --    dur dérive silencieusement au premier bump de `modversion` et personne ne s'en aperçoit
    --    — un afficheur ne doit pas porter une donnée qui n'a pas de source.
    self:drawTextRight(string.format("bank %d, %d, %d", self.bx or 0, self.by or 0, self.bz or 0),
                       cx + cw, hy, PHOS.r, PHOS.g, PHOS.b, 0.55, UIFont.Small)

    -- ── Bandeau RÉSEAU ─────────────────────────────────────────────────────────────────────
    -- Répond à « est-ce que je tiens la nuit ? » sans descendre dans la liste.
    local fhS2 = getTextManager():getFontHeight(UIFont.Small)
    local fhL  = getTextManager():getFontHeight(UIFont.Large)
    local ry   = hy + fhS2 + math.floor(6 * L.scale)
    self:drawRect(cx, ry, cw, 1, 0.35, PHOS.r, PHOS.g, PHOS.b)
    ry = ry + math.floor(6 * L.scale)

    local lblNet = self.netLinked and getText("IGUI_PSRWindow_Details_LinkedNetwork") or "BANK"
    self:drawText(lblNet, cx, ry + (fhL - fhS2) / 2, PHOS.r, PHOS.g, PHOS.b, 0.55, UIFont.Small)
    local nx = cx + math.floor(110 * L.scale)
    if self.netOK and (self.netCapacity or 0) > 0 then
        local chg = math.floor(self.netCharge or 0)
        local cap = math.floor(self.netCapacity or 0)
        local pct = math.floor(chg / cap * 100)
        local w1 = self:glow(tostring(chg), nx, ry, PHOS_HI, UIFont.Large)
        self:drawText("/" .. cap .. " Ah", nx + w1 + math.floor(6 * L.scale),
                      ry + (fhL - fhS2) / 2, PHOS.r, PHOS.g, PHOS.b, 0.55, UIFont.Small)
        -- Seuil de couleur : au-dessous de 25 % la réserve devient une alerte, pas une mesure.
        local pc = (pct < 25) and NOC or OKC
        self:glow(pct .. "%", nx + math.floor(150 * L.scale), ry, pc, UIFont.Large)
    else
        self:drawText("--", nx, ry + (fhL - fhS2) / 2, PHOS.r, PHOS.g, PHOS.b, 0.55, UIFont.Small)
    end
    -- `R-32` : la valeur RESEAU quand la liste est arrivee ; `netDrain` (= cette seule bank)
    -- n'est le repli que TANT QU'ELLE N'EST PAS ARRIVEE.
    -- ⚠️ ECRIT EN `if` EXPLICITE, PAS EN `a or b` : `netBilled` vaut **0** quand rien n'est
    --    facture, et **0 est TRUTHY en Lua** -- `self.netBilled or self.netDrain` ne se
    --    replierait donc jamais. Ca marche aujourd'hui uniquement parce que `netBilled` reste
    --    nil avant le 1er `computeBilledDrain`, c'est-a-dire par ORDRE D'INITIALISATION.
    --    Meme piege que le failsafe reseau (`0 or fallback`), deja paye une fois.
    local src = self.netDrain or 0
    if self.netBilled ~= nil then src = self.netBilled end
    local dr = math.floor(src * 10 + 0.5) / 10
    -- `Load` réutilise la clé existante `IGUI_PSRWindow_Details_BatteryDrain` : même grandeur,
    -- même mot que sur le panneau de la bank, et déjà traduite dans les 28 locales.
    self:drawTextRight(getText("IGUI_PSRWindow_Details_BatteryDrain") .. string.format(" %gAh   ", dr)
                       .. getText("IGUI_PSRComputerPanel_PanelOutput") .. " "
                       .. string.format("%.1f", perPanelOutput()) .. " Ah",
                       cx + cw, ry + (fhL - fhS2) / 2, PHOS.r, PHOS.g, PHOS.b, 0.55, UIFont.Small)

    -- Filet sous l'en-tête, puis ligne de colonnes — toutes deux calées sur `tableTop()`,
    -- l'unique origine de la grille.
    local top = self:tableTop()
    local fh  = getTextManager():getFontHeight(UIFont.Small)
    self:drawRect(cx, top - fh - math.floor(12 * L.scale), cw, 1, 0.35, PHOS.r, PHOS.g, PHOS.b)

    local colY = top - fh - math.floor(4 * L.scale)
    self:drawText(getText("IGUI_PSRComputerPanel_ColDevice"), L.colType,   colY, PHOS.r, PHOS.g, PHOS.b, 0.45, UIFont.Small)
    self:drawText(getText("IGUI_PSRComputerPanel_ColCount"),  L.colCount,  colY, PHOS.r, PHOS.g, PHOS.b, 0.45, UIFont.Small)
    self:drawText(getText("IGUI_PSRComputerPanel_ColDrain"),  L.colDrain,  colY, PHOS.r, PHOS.g, PHOS.b, 0.45, UIFont.Small)
    self:drawText(getText("IGUI_PSRComputerPanel_ColStatus"), L.colStatus, colY, PHOS.r, PHOS.g, PHOS.b, 0.45, UIFont.Small)

    -- Rows
    for i = p0, p1 do
        local row  = allRows[i]
        local rowY = top + (i - p0) * L.rowH

        -- Bande alternée : teintée phosphore et bornée à la DALLE, plus à toute la fenêtre —
        -- sinon elle débordait sur le cadre du moniteur.
        if i % 2 == 0 then
            self:drawRect(cx, rowY, cw, L.rowH, 0.06, PHOS.r, PHOS.g, PHOS.b)
        end

        if row.kind == "group" then
            local grp    = row.grp
            local allOff = grp.activeCount == 0
            local allOn  = grp.activeCount == grp.total

            -- Nom du type, préfixé du marqueur de dépliage. ⚠️ `+`/`-` en ASCII pur.
            local na   = allOff and 0.45 or 1
            local mark = (self.expanded[grp.dtype] and "- " or "+ ")
            local gname = mark .. getText("IGUI_PSRDeviceType_" .. grp.dtype)
            self:drawText(gname, L.colType, rowY + 4, PHOS.r, PHOS.g, PHOS.b, na, UIFont.Small)
            -- Toute la largeur du NOM déplie/replie — cible large, pas un chevron de 18 px.
            self:zone(L.colExpand, rowY, L.colCount - L.colExpand, L.rowH, function(s)
                s.expanded[grp.dtype] = (not s.expanded[grp.dtype]) or nil
                s.page = 1
                s:rebuildView()
            end)
            -- Bascule du groupe — uniquement pour les types réellement pilotables.
            if PSR_CONTROLLABLE[grp.dtype] then
                local lbl = allOff and getText("IGUI_PSRComputerPanel_Enable")
                                    or getText("IGUI_PSRComputerPanel_Disable")
                self:ctl(lbl, L.colBtn, rowY + 4, function(s)
                    s:applyControl(grp.dtype, nil, nil, nil, allOff)
                end)
            end

            -- Count: "(active/total)" when partial, "(n)" when all same
            local countText
            if allOn or allOff then
                countText = "(" .. grp.total .. ")"
            else
                countText = "(" .. grp.activeCount .. "/" .. grp.total .. ")"
            end
            self:drawText(countText, L.colCount, rowY + 4, PHOS.r, PHOS.g, PHOS.b, 0.8, UIFont.Small)

            -- Drain (active devices only)
            if grp.rate > 0 then
                self:drawText(fmtAh(grp.rate), L.colDrain, rowY + 4, PHOS.r, PHOS.g, PHOS.b, 0.8, UIFont.Small)
            end

            -- Status
            if allOff then
                self:drawText(getText("IGUI_PSRComputerPanel_StatusOff"), L.colStatus, rowY + 4, NOC.r, NOC.g, NOC.b, 1, UIFont.Small)
            elseif allOn then
                self:drawText(getText("IGUI_PSRComputerPanel_StatusOn"),  L.colStatus, rowY + 4, OKC.r, OKC.g, OKC.b, 1, UIFont.Small)
            else
                self:drawText(getText("IGUI_PSRComputerPanel_StatusPartial"), L.colStatus, rowY + 4, PHOS_HI.r, PHOS_HI.g, PHOS_HI.b, 1, UIFont.Small)
            end

        else  -- device row
            local dev = row.dev
            local grp = row.grp

            -- Coords — atténuées quand l'appareil est éteint. ⚠️ `->` en ASCII pur : les polices
            -- PZ ne garantissent rien au-delà de l'ASCII de base (le « ° » de PWS sortait en « ? »).
            local da = dev.active and 0.7 or 0.42
            self:drawText("  -> " .. dev.x .. "," .. dev.y, L.colType,  rowY + 4, PHOS.r, PHOS.g, PHOS.b, da, UIFont.Small)
            self:drawText(fmtAh(dev.rate),                  L.colDrain, rowY + 4, PHOS.r, PHOS.g, PHOS.b, 0.55, UIFont.Small)

            -- « go » : marche jusqu'à l'appareil. Même fonction qu'avant, seul l'appelant change.
            local gw = self:ctl(getText("IGUI_PSRComputerPanel_Go"), L.colGo, rowY + 4, function(s)
                s:goToSquare(dev.x, dev.y, dev.z)
            end)
            if PSR_CONTROLLABLE[grp.dtype] then
                local lbl = dev.active and getText("IGUI_PSRComputerPanel_Disable")
                                        or getText("IGUI_PSRComputerPanel_Enable")
                self:ctl(lbl, L.colGo + gw + math.floor(10 * L.scale), rowY + 4, function(s)
                    s:applyControl(grp.dtype, dev.x, dev.y, dev.z, not dev.active)
                end)
            end

            if dev.active then
                self:drawText(getText("IGUI_PSRComputerPanel_StatusOn"),  L.colStatus, rowY + 4, OKC.r, OKC.g, OKC.b, 1, UIFont.Small)
            else
                self:drawText(getText("IGUI_PSRComputerPanel_StatusOff"), L.colStatus, rowY + 4, NOC.r, NOC.g, NOC.b, 1, UIFont.Small)
            end
        end
    end

    if #allRows == 0 then
        self:drawText(getText("IGUI_PSRComputerPanel_NoDevices"), L.colType, top + 5, PHOS.r, PHOS.g, PHOS.b, 0.7, UIFont.Small)
    end

    -- ── Pied : pagination + commandes ──────────────────────────────────────────────────────
    local pages = self.pages or 1
    local fhF   = getTextManager():getFontHeight(UIFont.Small)
    local footY = sy + sh - fhF - math.floor(12 * L.scale)
    self:drawRect(cx, footY - math.floor(10 * L.scale), cw, 1, 0.35, PHOS.r, PHOS.g, PHOS.b)

    local fx = cx
    fx = fx + self:ctl("<", fx, footY, function(s)
            if s.page > 1 then s.page = s.page - 1; s:rebuildView() end
         end, self.page <= 1) + math.floor(10 * L.scale)
    local ptxt = string.format("%s %d/%d", getText("IGUI_PSR_Bank_Page"), self.page, pages)
    self:drawText(ptxt, fx, footY, PHOS_HI.r, PHOS_HI.g, PHOS_HI.b, 1, UIFont.Small)
    fx = fx + getTextManager():MeasureStringX(UIFont.Small, ptxt) + math.floor(10 * L.scale)
    self:ctl(">", fx, footY, function(s)
            if s.page < pages then s.page = s.page + 1; s:rebuildView() end
         end, self.page >= pages)

    -- Commandes à droite, mesurées puis posées de droite à gauche : un décalage en dur se
    -- décalerait au premier libellé traduit plus long (les 27 langues n'ont pas la même largeur).
    local tmF     = getTextManager()
    local closeTx = "[ " .. getText("IGUI_PSRComputerPanel_Close") .. " ]"
    local refrTx  = "[ " .. getText("IGUI_PSRComputerPanel_Refresh") .. " ]"
    local closeW  = tmF:MeasureStringX(UIFont.Small, closeTx)
    local refrW   = tmF:MeasureStringX(UIFont.Small, refrTx)
    local closeX  = cx + cw - closeW
    local refrX   = closeX - refrW - math.floor(18 * L.scale)
    self:ctl(getText("IGUI_PSRComputerPanel_Refresh"), refrX,  footY, function(s) s:onRefresh() end)
    self:ctl(getText("IGUI_PSRComputerPanel_Close"),   closeX, footY, function(s) s:close() end)

    -- ── Calque « verre » : scanlines + vignette, PAR-DESSUS le contenu dessiné ──────────────
    -- 🔑 Ordre volontaire, repris de `Functional Computers` : le verre est un calque FINAL.
    -- 📌 Les enfants `ISButton` sont rendus APRÈS `render()` par le gestionnaire d'UI, donc ils
    --    restent AU-DESSUS des scanlines : les commandes gardent leur netteté, seul le texte
    --    dessiné passe derrière le verre. C'est voulu — un bouton qu'on doit lire à travers une
    --    trame est un bouton qu'on clique de travers.
    -- ⚠️ Coût : sh/3 rectangles pleine largeur par frame (~165 à taille de base). C'est un aplat,
    --    pas un calcul — mais c'est le point que la maquette existait pour faire juger.
    for ly = sy, sy + sh - 1, SCAN_PITCH do
        self:drawRect(sx, ly, sw, 1, 0.30, 0, 0, 0)
    end
    -- Vignette approximée par 4 bandes de bord : pas de dégradé radial en PZ.
    local vb = math.floor(22 * L.scale)
    self:drawRect(sx, sy, sw, vb, 0.20, 0, 0, 0)
    self:drawRect(sx, sy + sh - vb, sw, vb, 0.20, 0, 0, 0)
    self:drawRect(sx, sy, vb, sh, 0.16, 0, 0, 0)
    self:drawRect(sx + sw - vb, sy, vb, sh, 0.16, 0, 0, 0)
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Open / close
-- ──────────────────────────────────────────────────────────────────────────────

function PSRComputerPanel:close()
    self:removeFromUIManager()
    if JoypadState and JoypadState.players and
       JoypadState.players[(self.player or 0) + 1] then
        setPrevFocusForPlayer(self.player)
    end
end

function PSRComputerPanel.OnOpen(player, computer)
    local linkedBank = computer:getModData().PSR_linkedBank
    if not linkedBank then return end

    local instance = PSRComputerPanel.instance
    if not instance then
        -- Pre-compute layout to know the right window size for current Font Size.
        -- :new() will recompute and store o.L (same result).
        local layout = computeLayout()
        local winH = math.floor(20 * layout.scale) + math.floor(28 * layout.scale)
                   + ROWS_PER_PAGE * layout.rowH
                   + math.floor(28 * layout.scale) + math.floor(34 * layout.scale) + 6
        instance = PSRComputerPanel:new(80, 80, layout.winW, winH)
        if ISLayoutManager and ISLayoutManager.RegisterWindow then
            ISLayoutManager.RegisterWindow("PSRComputerPanel", PSRComputerPanel, instance)
        end
    end

    instance.player   = player
    instance.bx       = linkedBank.x
    instance.by       = linkedBank.y
    instance.bz       = linkedBank.z
    -- Store computer square for proximity check
    local compSq = computer:getSquare()
    if compSq then
        instance.cx = compSq:getX()
        instance.cy = compSq:getY()
        instance.cz = compSq:getZ()
    end
    instance.loaded   = false
    instance.devices  = {}
    instance.expanded = {}
    instance.page     = 1
    instance.allRows  = {}
    -- Horloges REELLES (ms), pas des compteurs de frames — voir update(). On les repousse a
    -- l'ouverture pour ne pas declencher un `silentFetch` immediat juste apres le `fetchDeviceList`
    -- explicite ci-dessous (l'instance est un singleton reutilise d'une ouverture a l'autre).
    local nowOpen = getTimestampMs()
    instance.autoRefreshAt = nowOpen + 10000
    instance.proximityAt   = nowOpen + 2000
    instance.linkCheckAt   = nowOpen + 500
    -- Bandeau réseau : relu IMMÉDIATEMENT à l'ouverture (0, pas nowOpen + 1000), sinon la
    -- première seconde afficherait « -- » sur un écran qu'on vient d'allumer.
    instance.netReadAt     = 0
    instance.netOK         = false
    if instance.lblLoading then instance.lblLoading:setVisible(true)  end
    if instance.btnPrev    then instance.btnPrev:setVisible(false)    end
    if instance.btnNext    then instance.btnNext:setVisible(false)    end
    if instance.lblPage    then instance.lblPage:setVisible(false)    end
    instance:clearRows()
    instance:addToUIManager()
    instance:fetchDeviceList()
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Server → client (dedicated MP: receive updated device list)
-- ──────────────────────────────────────────────────────────────────────────────

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PSR" then return end

    if command == "deviceList" then
        local instance = PSRComputerPanel.instance
        if not instance then return end
        if args.bx ~= instance.bx or args.by ~= instance.by or args.bz ~= instance.bz then return end
        -- ⚡ 2026-08-13 : l'état du réseau arrive AVEC la liste. Sur un client de dédié,
        -- c'est la SEULE source disponible (`PSR.PBSystem_Server` y est nil).
        -- ⚠️ `args.supplies` peut être nil si le serveur tourne une version antérieure :
        --    on ne le convertit PAS en `false` (ce qui bloquerait tout chez ce joueur),
        --    on garde nil et la garde traite « inconnu » comme « autorisé ». Un mod à jour
        --    des deux côtés donne toujours un booléen.
        instance.netSupplies = args.supplies
        -- v1.71 — même traitement, et le `nil` est SIGNIFIANT (voir `networkAnyBankOn`).
        instance.netAnyOn = args.netAnyOn
        instance:refreshDevices(args.devices or {})

    elseif command == "applyDeviceToggle" then
        -- Server instructs this client to apply the visual toggle using native client-side APIs.
        -- Client-side calls let PZ handle its own sync (transmitModData client→server→all clients).
        if not args.devices then return end
        for _, dev in ipairs(args.devices) do
            local sq = getSquare(dev.x, dev.y, dev.z)
            if sq then
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local obj = objs:get(i)
                    if obj then
                        if args.dtype == "light" then
                            if instanceof(obj, "IsoLightSwitch") then
                                -- Avoid toggling wall switches (dtype "switch" is handled separately)
                                local sq2 = obj:getSquare()
                                local isWallSwitch = sq2 and sq2.getProperties
                                    and sq2:getProperties():get("CustomName") == "Switch"
                                if not isWallSwitch then
                                    -- toggle() fires Java-level network sync
                                    if obj:isActivated() ~= args.on then obj:toggle() end
                                end
                            end
                        elseif args.dtype == "tv" then
                            if instanceof(obj, "IsoTelevision") then
                                -- Same fix as the server-side psrSetDeviceState: refresh the cached
                                -- power flag first, or vanilla's own tick reverts IsTurnedOn shortly after.
                                if obj.checkHaveElectricity then obj:checkHaveElectricity() end
                                local dd = obj:getDeviceData()
                                if dd then dd:setIsTurnedOn(args.on); obj:transmitModData() end
                            end
                        elseif args.dtype == "stove" then
                            -- 🔑 Jumeau CLIENT de la branche serveur ajoutée le 2026-08-13.
                            --    `stove` était produit par `psrGetDeviceType` et traité NULLE PART :
                            --    listé, facturé, impossible à éteindre. Corriger un seul des deux
                            --    côtés aurait laissé le défaut entier en dédié, où c'est CE handler
                            --    qui applique le changement — la moitié du correctif est ici.
                            -- 📚 Doc lue : `IsoStove.setActivated(boolean)` existe ; `isActivated()`
                            --    N'EXISTE PAS (le getter est `Activated()`). Garde conservée.
                            if instanceof(obj, "IsoStove") then
                                if obj.setActivated then obj:setActivated(args.on) end
                            end
                        elseif args.dtype == "appliance" then
                            -- 🔑 Jumeau CLIENT de la branche serveur (2026-08-13). Un `appliance`
                            --    porte un `DeviceData`, donc le même on/off que TV et radio.
                            --    ⚠️ Aucun `instanceof` ici : justement, un appliance n'est NI
                            --    `IsoTelevision` NI `IsoRadio` — c'est sa définition. On teste
                            --    la CAPACITÉ (`getDeviceData`), pas la classe.
                            if obj.checkHaveElectricity then obj:checkHaveElectricity() end
                            if obj.getDeviceData then
                                local ok, dd = pcall(function() return obj:getDeviceData() end)
                                if ok and dd then dd:setIsTurnedOn(args.on); obj:transmitModData() end
                            end
                        elseif args.dtype == "radio" then
                            if instanceof(obj, "IsoRadio") then
                                if obj.checkHaveElectricity then obj:checkHaveElectricity() end
                                local dd = obj:getDeviceData()
                                if dd then dd:setIsTurnedOn(args.on); obj:transmitModData() end
                            end
                        elseif args.dtype == "washer" then
                            if instanceof(obj, "IsoClothingWasher") or instanceof(obj, "IsoStackedWasherDryer") then
                                obj:setActivated(args.on); obj:transmitModData()
                            end
                        elseif args.dtype == "dryer" then
                            if instanceof(obj, "IsoClothingDryer") or instanceof(obj, "IsoCombinationWasherDryer") then
                                obj:setActivated(args.on); obj:transmitModData()
                            end
                        elseif args.dtype == "switch" then
                            -- Direct toggle from Lua (no adjacency needed in dedicated MP).
                            -- Known B42 piège: ceiling light GroupName cascade may not
                            -- always fire — standalone switches reliably toggle.
                            if instanceof(obj, "IsoLightSwitch") then
                                if obj:isActivated() ~= args.on then obj:toggle() end
                            end
                        elseif args.dtype == "coldunit" then
                            -- PFR Cold Unit cross-mod support. Soft check on modData tag —
                            -- no runtime dependency on PFR being loaded.
                            if obj.hasModData and obj:hasModData() and obj:getModData().PFR_isColdUnit == true then
                                obj:getModData().PFR_on = args.on
                                obj:transmitModData()
                            end
                        elseif args.dtype == "fridge" or args.dtype == "freezer" or args.dtype == "fridgeFreezer" then
                            -- Apply the container type swap client-side so every client sees the
                            -- fridge/freezer turn off/on (cooling + container title). Same "_off" types
                            -- as the Fridges Off! mod; PZ persists the container type in the save.
                            if obj.getContainerByType then
                                -- Only act on objects matching the requested dtype: a fridge and a
                                -- freezer can be two distinct objects on the same tile → don't swap the
                                -- wrong one (mirrors the server-side psrGetDeviceType classification).
                                local hasF = (obj:getContainerByType("fridge")  ~= nil) or (obj:getContainerByType("fridge_off")  ~= nil)
                                local hasZ = (obj:getContainerByType("freezer") ~= nil) or (obj:getContainerByType("freezer_off") ~= nil)
                                local objType = (hasF and hasZ) and "fridgeFreezer" or (hasF and "fridge") or (hasZ and "freezer") or nil
                                if objType == args.dtype then
                                    local fc = obj:getContainerByType(args.on and "fridge_off" or "fridge")
                                    if fc then fc:setType(args.on and "fridge" or "fridge_off") end
                                    local zc = obj:getContainerByType(args.on and "freezer_off" or "freezer")
                                    if zc then zc:setType(args.on and "freezer" or "freezer_off") end
                                    if obj.checkHaveElectricity then obj:checkHaveElectricity() end
                                    -- Refresh open loot windows so an open fridge UI isn't left stale.
                                    local pd = getPlayer() and getPlayerData(getPlayer():getPlayerNum())
                                    if pd then
                                        if pd.playerInventory then pd.playerInventory:refreshBackpacks() end
                                        if pd.lootInventory   then pd.lootInventory:refreshBackpacks()   end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

PSR.ComputerPanel = PSRComputerPanel
