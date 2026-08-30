--[[ ═══════════════════════════════════════════════════════════════════════════════════════════
     PSR — PANNEAU DE LA BATTERY BANK  (refonte 2026-08-07, maquette validée par le Commandeur)
     ═══════════════════════════════════════════════════════════════════════════════════════════

     Un CONTRÔLEUR DE CHARGE : boîtier, dalle LCD rétroéclairée, touches membrane.
     860 × 600, trois pages (MAIN / DETAIL / DIAG) sur le MÊME instrument — une seule fenêtre,
     et le clic droit sur la bank ne porte plus qu'une entrée.

     🔑 LE LANGAGE GRAPHIQUE VIENT DE PWS, PAS SON GABARIT. `drawDigit`, la palette de la dalle
        et les traits gravés sont repris verbatim de `PWSPanel.lua` : c'est le même fabricant.
        Mais PWS est un afficheur domestique posé sur un meuble ; une bank est une armoire
        technique. Reprendre ses 470 px aurait été confondre le style et l'échelle.

     🛑 CE QUE CE FICHIER NE FAIT PAS, ET C'EST DÉLIBÉRÉ :
        · il n'écrit AUCUNE modData         · il ne réimplémente AUCUN prédicat de garde
        · il ne construit AUCUNE TimedAction — il appelle `PSR.UI.actions.*`, le chemin testé,
          où vivent `walkAdj`, la garde « bank ramassée entre l'ouverture et le clic » (2026-08-04)
          et l'interruptibilité. Une copie « simplifiée » perdrait les trois EN SILENCE.

     ⚠️ ASCII PUR dans toute chaîne dessinée : les polices PZ ne garantissent rien au-delà de
        l'ASCII de base (le « ° » de PWS sortait en « ? »). Donc `OK`, `+`, `-`, jamais `✓` ni `→`.
     ═══════════════════════════════════════════════════════════════════════════════════════════ ]]

require "ISUI/ISPanel"
require "PSR/UI/PSRUI"
local PSR = require "PSR/Utilities"

local PSRBankPanel = ISPanel:derive("PSRBankPanel")
PSRBankPanel.instance = nil

-- ── Palette (dalle et encre : verbatim PWSPanel.lua) ───────────────────────────────────────
local LCD    = { r = 0.663, g = 0.788, b = 0.839 }
local LCD_HI = { r = 0.737, g = 0.855, b = 0.902 }
local INK    = { r = 0.086, g = 0.125, b = 0.165 }
local BEZEL  = { r = 0.086, g = 0.090, b = 0.102 }
local SILVER = { r = 0.604, g = 0.620, b = 0.639 }
local KEYBG  = { r = 0.129, g = 0.145, b = 0.165 }
local KEYTXT = { r = 0.788, g = 0.812, b = 0.835 }
local AMBER  = { r = 0.878, g = 0.635, b = 0.290 }
local GREEN  = { r = 0.310, g = 0.816, b = 0.467 }

local GHOST_A = 0.045   -- segments éteints : se devinent, ne se lisent pas (valeur corrigée en jeu)
local ETCH_A  = 0.26
local PAD     = 16
local TRACK   = 1       -- interlettrage manuel (voir `spaced`)

local SEGMAP = {
    ["0"]="abcdef", ["1"]="bc",     ["2"]="abdeg",  ["3"]="abcdg",   ["4"]="bcfg",
    ["5"]="acdfg",  ["6"]="acdefg", ["7"]="abc",    ["8"]="abcdefg", ["9"]="abcdfg",
    ["-"]="g",      [" "]="",
}

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Primitives de dessin
-- ═══════════════════════════════════════════════════════════════════════════════════════════
function PSRBankPanel:drawDigit(x, y, w, h, t, ch)
    local on = SEGMAP[ch] or ""
    local hh = h / 2
    local function seg(key, sx, sy, sw, sh)
        local lit = string.find(on, key, 1, true) ~= nil
        self:drawRect(sx, sy, sw, sh, lit and 1 or GHOST_A, INK.r, INK.g, INK.b)
    end
    seg("a", x + t,     y,            w - 2*t, t)
    seg("b", x + w - t, y + t,        t,       hh - t)
    seg("c", x + w - t, y + hh,       t,       hh - t)
    seg("d", x + t,     y + h - t,    w - 2*t, t)
    seg("e", x,         y + hh,       t,       hh - t)
    seg("f", x,         y + t,        t,       hh - t)
    seg("g", x + t,     y + hh - t/2, w - 2*t, t)
end

function PSRBankPanel:drawNumber(x, y, h, text)
    local w, t, gap = h * 0.56, math.max(2, h * 0.11), h * 0.10
    local cx = x
    for i = 1, #text do
        self:drawDigit(cx, y, w, h, t, text:sub(i, i))
        cx = cx + w + gap
    end
    return cx - x - gap
end

-- 🔑 L'INTERLETTRAGE N'EXISTE PAS DANS `drawText`. Sans lui un libellé se lit comme du texte
--    d'interface, pas comme une sérigraphie d'instrument. On le fabrique caractère par caractère.
-- ⚠️ Un appel de rendu PAR CARACTÈRE ⇒ réservé aux libellés courts. Jamais sur une liste.
function PSRBankPanel:spaced(text, x, y, r, g, b, a, font)
    local tm, cx = getTextManager(), x
    for i = 1, #text do
        local ch = text:sub(i, i)
        self:drawText(ch, cx, y, r, g, b, a, font)
        cx = cx + tm:MeasureStringX(font, ch) + TRACK
    end
    return cx - x - TRACK
end

function PSRBankPanel:label(text, x, y)
    return self:spaced(text:upper(), x, y, INK.r, INK.g, INK.b, 0.62, UIFont.NewSmall)
end

function PSRBankPanel:valueRight(text, x, y)
    self:drawTextRight(text, x, y, INK.r, INK.g, INK.b, 1, UIFont.Small)
end

-- Trait gravé : filet sombre + highlight dessous. C'est le highlight qui fait la gravure.
function PSRBankPanel:etch(x, y, w)
    self:drawRect(x, y,     w, 1, ETCH_A, INK.r, INK.g, INK.b)
    self:drawRect(x, y + 1, w, 1, 0.35, 1, 1, 1)
end

function PSRBankPanel:vetch(x, y, h)
    self:drawRect(x,     y, 1, h, ETCH_A, INK.r, INK.g, INK.b)
    self:drawRect(x + 1, y, 1, h, 0.35, 1, 1, 1)
end

function PSRBankPanel:pill(text, x, y, inv)
    local tm = getTextManager()
    local fh = tm:getFontHeight(UIFont.NewSmall)
    local w  = tm:MeasureStringX(UIFont.NewSmall, text) + (#text - 1) * TRACK + 12
    if inv then
        self:drawRect(x, y, w, fh + 4, 1, INK.r, INK.g, INK.b)
        self:spaced(text, x + 6, y + 2, LCD.r, LCD.g, LCD.b, 1, UIFont.NewSmall)
    else
        self:drawRectBorder(x, y, w, fh + 4, 1, INK.r, INK.g, INK.b)
        self:spaced(text, x + 6, y + 2, INK.r, INK.g, INK.b, 1, UIFont.NewSmall)
    end
    return w
end

--- Largeur qu'une touche doit avoir pour contenir son libellé.
--- 🔴 CRÉÉE APRÈS UN DÉBORDEMENT EN JEU (2026-08-07) : « DISCONNECT SOLAR COMPUTER » sortait de
---    sa touche de 200 px. Le réflexe était de rogner la touche voisine — c'eût été rejouer le
---    défaut, en anglais seulement.
--- 🔑 **Une largeur en dur est une largeur juste dans UNE langue.** PSR est publié en 27 langues :
---    le même libellé est plus long en allemand, en russe, en portugais. La seule forme qui tient
---    est de MESURER le texte traduit et d'en déduire la touche — jamais l'inverse.
---    C'est la leçon PWS (« on ne devine plus la hauteur du texte, on la MESURE »), appliquée à
---    la largeur.
--- ⚠️ L'interlettrage manuel compte dans la mesure : `MeasureStringX` ne le connaît pas.
function PSRBankPanel:keyWidth(text, minW)
    local up = text:upper()
    local w  = getTextManager():MeasureStringX(UIFont.NewSmall, up) + (#up - 1) * TRACK + 28
    return math.max(w, minW or 0)
end

--- Bouton dessiné SUR la dalle (page DIAG). Contour d'encre, pas une touche membrane : une
--- touche du bandeau appartient au boîtier, un bouton d'écran appartient à l'affichage.
function PSRBankPanel:lcdButton(text, x, y, fn, enabled)
    local tm = getTextManager()
    local fh = tm:getFontHeight(UIFont.Small)
    local w  = tm:MeasureStringX(UIFont.Small, text) + 24
    local h  = fh + 8
    local a  = enabled and 1 or 0.3
    self:drawRectBorder(x, y, w, h, a, INK.r, INK.g, INK.b)
    self:drawText(text, x + 12, y + 4, INK.r, INK.g, INK.b, a, UIFont.Small)
    if fn and enabled then self:zone(x, y, w, h, fn) end
    return w, h
end

-- ── Zones cliquables ───────────────────────────────────────────────────────────────────────
function PSRBankPanel:zone(x, y, w, h, fn)
    self.zones[#self.zones + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

function PSRBankPanel:onMouseDown(x, y)
    for _, z in ipairs(self.zones or {}) do
        if x >= z.x and x <= z.x + z.w and y >= z.y and y <= z.y + z.h then
            z.fn(self); return true
        end
    end
    return ISPanel.onMouseDown(self, x, y)
end

-- ── Touche membrane ────────────────────────────────────────────────────────────────────────
-- `state` : "idle" | "lit" (page courante) | "off" (indisponible)
function PSRBankPanel:key(text, x, y, w, h, state, fn)
    local lit = (state == "lit")
    if lit then
        self:drawRect(x, y, w, h,     1, AMBER.r, AMBER.g, AMBER.b)
        self:drawRect(x, y, w, h / 2, 0.22, 1, 1, 1)      -- dégradé approximé (2 aplats)
    else
        self:drawRect(x, y, w, h,     1, KEYBG.r, KEYBG.g, KEYBG.b)
        self:drawRect(x, y, w, h / 2, 0.10, 1, 1, 1)
    end
    self:drawRect(x, y,         w, 1, 0.16, 1, 1, 1)      -- arête éclairée
    self:drawRect(x, y + h - 1, w, 1, 0.50, 0, 0, 0)      -- ombre inférieure

    local tm = getTextManager()
    local up = text:upper()
    local tw = tm:MeasureStringX(UIFont.NewSmall, up) + (#up - 1) * TRACK
    local ty = y + (h - tm:getFontHeight(UIFont.NewSmall)) / 2
    local a  = (state == "off") and 0.35 or 1
    if lit then self:spaced(up, x + (w - tw) / 2, ty, 0.09, 0.07, 0.04, 1, UIFont.NewSmall)
    else        self:spaced(up, x + (w - tw) / 2, ty, KEYTXT.r, KEYTXT.g, KEYTXT.b, a, UIFont.NewSmall) end
    if fn and state ~= "off" then self:zone(x, y, w, h, fn) end
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- LECTURE DES DONNÉES — cadencée à 1 s réelle
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 🔴 `getLinkedBanksPanelInfo` est un BFS sur tout le réseau, et le balayage d'adjacence lit
--    4 cases + leurs objets. Au rendu, ce serait un parcours complet PAR IMAGE, dont le coût
--    croît avec la taille du réseau. Défaut exact corrigé le 04/08 sur la vue Details.
-- 🔑 Horloge en MILLISECONDES, jamais un compteur de frames : à 144 fps un compteur voit sa
--    période divisée par cinq — c'est ce qui avait multiplié par 5 la charge serveur en dédié.
local function resolveBank(x, y, z)
    local pb = PSR.PBSystem_Client and PSR.PBSystem_Client:getLuaObjectAt(x, y, z)
    if pb then return pb end
    -- Repli : on reconstruit depuis la modData de l'IsoObject. ⚠️ C'est CE chemin qui rend la
    -- lecture valable en client de dédié — il passe par la modData répliquée par le moteur,
    -- jamais par `PBSystem_Server`, qui n'existe pas côté client.
    local sq  = getSquare(x, y, z)
    local iso = sq and PSR.PBSystem_Client and PSR.PBSystem_Client:getIsoObjectOnSquare(sq)
    if not iso then return nil end
    local PowerBank = require("PSR/Powerbank/PowerBankObject_Client")
    local pb2 = { x = x, y = y, z = z, luaSystem = PSR.PBSystem_Client }
    setmetatable(pb2, PowerBank)
    return pb2
end

function PSRBankPanel:refresh()
    self.readAt = getTimestampMs() + 1000
    self.ok = false

    local pb = resolveBank(self.bx, self.by, self.bz)
    if not pb then return end
    pb:updateFromIsoObject()
    self.pb = pb

    local iso = pb:getIsoObject()
    self.isOn = iso and iso:getModData()["on"] or false

    local cap = pb.maxcapacity or 0
    self.capacity = cap
    self.charge   = pb.charge or 0
    self.pct      = cap > 0 and math.floor(self.charge / cap * 100) or 0
    self.drain    = pb.drain or 0
    self.npanels  = pb.npanels or 0

    local sys = pb.luaSystem
    self.solarMax = sys and sys:getMaxSolarOutput(self.npanels) or 0
    self.solarNow = sys and sys:getModifiedSolarOutput(self.npanels) or 0
    -- `shouldDrain()` : tant que le réseau municipal couvre la charge, les batteries ne se
    -- vident pas réellement. Le solde doit refléter ça, sinon on annonce une décharge fictive.
    self.net = self.solarNow - ((pb.shouldDrain and pb:shouldDrain()) and self.drain or 0)

    local nPanels, links, nCharge, nDrain, nCapacity = PSR.WorldUtil.getLinkedBanksPanelInfo(pb)
    self.linked      = links and #links > 0 or false
    self.linkCount   = links and #links or 0
    -- 🔴 DEUX GRANDEURS DISTINCTES, QUE J'AVAIS CONFONDUES. `getLinkedBanksPanelInfo` fait un
    --    **BFS** : `links` contient TOUT le réseau atteignable (`WorldUtilities.lua:506-517`,
    --    file d'attente + `visited`), pas les voisines directes. Or « Unlink all » ne porte que
    --    sur les liens DIRECTS de cette bank — c'est `#pb.PSR_linkedBanks` que l'ancien menu
    --    testait (`> 1`). Sur une chaîne A—B—C, ma version aurait activé la touche pour A, qui
    --    n'a pourtant qu'un seul lien à défaire.
    -- 📌 Le mot « linked » désignait deux choses ; seul le code le disait.
    self.directLinks = #(pb.PSR_linkedBanks or {})
    self.netPanels   = nPanels or 0
    self.netCharge   = nCharge or 0
    self.netDrain    = nDrain or 0
    self.netCapacity = nCapacity or 0

    -- ── Boussole : état des 4 côtés ────────────────────────────────────────────────────────
    -- 🛑 AUCUNE ADJACENCE INVENTÉE. `getAdjacentBankSquares` balaie exactement les 4 cases
    --    orthogonales et ne rend que celles portant une bank ; `getDirection` rend exactement
    --    "N"/"S"/"E"/"W". La boussole est donc la STRUCTURE du code, pas une interprétation.
    local dirs = { N = "none", S = "none", E = "none", W = "none" }
    local iso2 = {}
    local linkedSet = {}
    for _, l in ipairs(pb.PSR_linkedBanks or {}) do
        linkedSet[l.x .. "_" .. l.y .. "_" .. l.z] = true
    end
    for _, sq in ipairs(PSR.WorldUtil.getAdjacentBankSquares(self.bx, self.by, self.bz)) do
        local d = PSR.WorldUtil.getDirection(self.bx, self.by, sq:getX(), sq:getY())
        dirs[d] = linkedSet[sq:getX() .. "_" .. sq:getY() .. "_" .. sq:getZ()] and "on" or "free"
        iso2[d] = PSR.WorldUtil.findTypeOnSquare(sq, "PowerBank")
    end
    self.dirs, self.dirIso = dirs, iso2

    -- ── Ordinateur ─────────────────────────────────────────────────────────────────────────
    -- 🔴 NE PAS LIRE `pb.PSR_computer` : `PowerBank:fromModData` (client) recopie 11 champs et
    --    celui-là n'en fait PAS partie ⇒ il vaut **toujours nil** côté client. J'y avais cru,
    --    et le panneau annonçait « pas d'ordinateur » sur une bank qui en avait un.
    --    📌 Écart **stocké → exposé** : la donnée est bien dans la modData, mais l'objet Lua ne
    --    l'expose pas. *Un objet de commodité ne reflète que ce que son constructeur recopie.*
    -- ⚠️ Corollaire non corrigé ici : `WorldUtil.findLinkedComputer(pb)` lit `pb.PSR_computer`,
    --    donc rendrait nil pour TOUT appelant qui lui passe un objet client. On lui fournit donc
    --    une table minimale portant la coordonnée lue directement dans la modData.
    local md = iso and iso:getModData() or {}
    self.compCoord = md.PSR_computer

    if self.compCoord then
        local comp, known = PSR.WorldUtil.findLinkedComputer(
            { x = self.bx, y = self.by, z = self.bz, PSR_computer = self.compCoord })
        -- 🔑 TROIS états, pas deux. `known == false` = chunk non chargé : **on ne sait pas**.
        --    Afficher « non » sur une absence d'information est l'erreur que ce mod interdit
        --    partout ailleurs (règle payée sur PFR : un faux dégel perd la nourriture).
        self.compState = (comp and "yes") or (known and "no" or "unknown")
    else
        self.compState = "no"
    end
    self.ok = true
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Formatage
-- ═══════════════════════════════════════════════════════════════════════════════════════════
local function fmtTime(h)
    if type(h) ~= "number" or h ~= h or h == math.huge then return "--" end
    h = math.abs(h)
    return string.format("%dd %dh %02dm", math.floor(h / 24), math.floor(h % 24),
                         math.floor((h - math.floor(h)) * 60))
end

local function signed(v)
    local r = math.floor(math.abs(v) * 10 + 0.5) / 10
    return (v < 0 and "- " or "+ ") .. string.format("%g", r) .. " Ah"
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- PAGE MAIN
-- ═══════════════════════════════════════════════════════════════════════════════════════════
function PSRBankPanel:renderMain(lx, ly, lw, lh, splitX)
    local tm   = getTextManager()
    local fhS  = tm:getFontHeight(UIFont.Small)
    local fhNS = tm:getFontHeight(UIFont.NewSmall)
    local line = fhS + 5

    -- ── Colonne gauche ─────────────────────────────────────────────────────────────────────
    local x, y   = lx + 18, ly + 14
    local colW   = splitX - x - 18

    self:label(getText("IGUI_PSRWindowsSumaryTab_BatteryLevel"), x, y)
    self:pill(self.isOn and getText("UI_Yes") or getText("UI_No"), x + colW - 46, y - 2, self.isOn)
    y = y + fhNS + 10

    local used = self:drawNumber(x, y, 76, tostring(self.pct))
    self:drawText("%", x + used + 10, y + 46, INK.r, INK.g, INK.b, 1, UIFont.Large)
    self:valueRight(string.format("%d / %d Ah", math.floor(self.charge), math.floor(self.capacity)),
                    x + colW, y + 58)
    y = y + 76 + 14

    -- Bargraphe 12 blocs. 🔑 ARRONDI AU BLOC INFÉRIEUR : arrondir au supérieur annoncerait 100 %
    -- à 96 %, donc PLUS que la mesure. Un afficheur ne doit jamais flatter la réserve.
    local nb, bh, bgap = 12, 18, 4
    local bw  = (colW - bgap * (nb - 1)) / nb
    local lit = math.floor(self.pct / 100 * nb)
    for i = 0, nb - 1 do
        local bx2 = x + i * (bw + bgap)
        self:drawRect(bx2, y, bw, bh, i < lit and 0.88 or 0.09, INK.r, INK.g, INK.b)
        self:drawRectBorder(bx2, y, bw, bh, 0.35, INK.r, INK.g, INK.b)
    end
    y = y + bh + 12
    self:etch(x, y, colW); y = y + 12

    local function kv(k, v)
        self:label(k, x, y + 1); self:valueRight(v, x + colW, y); y = y + line
    end
    -- 🔑 `Load` réutilise `IGUI_PSRWindow_Details_BatteryDrain` : la clé existe et est traduite
    --    dans les 28 locales. Créer un synonyme aurait ajouté 28 traductions pour dire la même
    --    chose — et une divergence de vocabulaire entre deux écrans du même mod.
    kv(getText("IGUI_PSR_Bank_SolarIn"), signed(self.solarNow))
    kv(getText("IGUI_PSRWindow_Details_BatteryDrain"), signed(-self.drain))
    kv(getText("IGUI_PSR_Bank_Net"),     signed(self.net))
    y = y + 2; self:etch(x, y, colW); y = y + 12

    if self.net > 0 and self.capacity > self.charge then
        kv(getText("IGUI_PSRWindowsSumaryTab_ChargedIn"), fmtTime((self.capacity - self.charge) / self.net))
    elseif self.net < 0 and self.charge > 0 then
        kv(getText("IGUI_PSRWindowsSumaryTab_DischargedIn"), fmtTime(self.charge / -self.net))
    else
        kv(getText("IGUI_PSRWindowsSumaryTab_BatteryStatus"), getText("IGUI_PSRWindowsSumaryTab_NotCharging"))
    end
    if self.charge > 0 and self.drain > 0 then
        kv(getText("IGUI_PSRWindowsSumaryTab_BatteryRemaining"), fmtTime(self.charge / self.drain))
    end
    y = y + 2; self:etch(x, y, colW); y = y + 12

    self:label(getText("IGUI_PSRWindowsSumaryTab_PanelCount"), x, y + 8)
    self:drawNumber(x + 76, y, 30, tostring(self.npanels))
    -- Ensoleillement = sortie courante / sortie maximale. Cinq blocs suffisent : c'est une
    -- tendance, pas une mesure — un chiffre inviterait à une précision qu'on n'a pas.
    self:label(getText("IGUI_PSR_Bank_Sun"), x + colW - 108, y + 8)
    local sun = self.solarMax > 0 and math.floor(self.solarNow / self.solarMax * 5) or 0
    for i = 0, 4 do
        self:drawRect(x + colW - 74 + i * 15, y + 6, 12, 12,
                      i < sun and 0.88 or 0.09, INK.r, INK.g, INK.b)
    end
    y = y + 34

    local status
    if self.drain > self.solarMax     then status = getText("IGUI_PSRWindowsSumaryTab_NoEnoughPanels")
    elseif self.drain > self.solarNow then status = getText("IGUI_PSRWindowsSumaryTab_NoEnoughSun")
    else                                   status = getText("IGUI_PSRWindowsSumaryTab_Working") end
    -- Réutilise l'en-tête de colonne du terminal : même mot, même écran-frère, clé déjà traduite.
    self:label(getText("IGUI_PSRComputerPanel_ColStatus"), x, y + 1)
    self:valueRight(status, x + colW, y)

    -- ── Colonne droite ─────────────────────────────────────────────────────────────────────
    local rx = splitX + 18
    local rw = lx + lw - rx - 18
    local ry = ly + 14

    self:label(getText("IGUI_PSRWindow_Details_LinkedNetwork"), rx, ry); ry = ry + fhNS + 8
    local function nv(k, v)
        self:label(k, rx, ry + 1); self:valueRight(v, rx + rw, ry); ry = ry + line
    end
    if self.linked then
        nv(getText("IGUI_PSRWindow_Details_LinkedBanks"),     tostring(self.linkCount))
        nv(getText("IGUI_PSRWindow_Details_NetworkCapacity"), math.floor(self.netCapacity) .. " Ah")
        nv(getText("IGUI_PSRWindow_Details_NetworkPanels"),   tostring(self.netPanels))
        -- 🔴 Recharge réseau : capacité RÉSEAU divisée par un débit RÉSEAU. Mélanger la capacité
        --    d'UNE bank avec le débit de TOUT le réseau est le défaut corrigé le 07/08 dans les
        --    deux vues — il rendait l'estimation d'autant plus optimiste qu'il y avait de banks.
        local netSolar = self.pb.luaSystem and self.pb.luaSystem:getModifiedSolarOutput(self.netPanels) or 0
        local rate = netSolar - self.netDrain
        if rate > 0 and self.netCapacity > self.netCharge then
            nv(getText("IGUI_PSRWindow_Details_NetworkRecharge"),
               fmtTime((self.netCapacity - self.netCharge) / rate))
        end
        if self.netDrain > 0 and self.netCharge > 0 then
            nv(getText("IGUI_PSRWindowsSumaryTab_NetworkReserves"), fmtTime(self.netCharge / self.netDrain))
        end
    else
        nv(getText("IGUI_PSRWindow_Details_LinkedBanks"), getText("UI_No"))
    end
    ry = ry + 2; self:etch(rx, ry, rw); ry = ry + 14

    -- ── LA BOUSSOLE ────────────────────────────────────────────────────────────────────────
    self:label(getText("IGUI_PSRWindow_Details_LinkedBanks"), rx, ry); ry = ry + fhNS + 8
    local cwid, chgt, cg = 54, 40, 5
    local cx0 = rx + (rw - (cwid * 3 + cg * 2)) / 2
    local cells = { { k = "N", c = 1, r = 0 }, { k = "W", c = 0, r = 1 },
                    { k = "E", c = 2, r = 1 }, { k = "S", c = 1, r = 2 } }
    for _, cell in ipairs(cells) do
        local bx2 = cx0 + cell.c * (cwid + cg)
        local by2 = ry  + cell.r * (chgt + cg)
        local st  = (self.dirs and self.dirs[cell.k]) or "none"
        local txt = cell.k .. (st == "on" and " OK" or (st == "free" and " +" or ""))
        local tw  = tm:MeasureStringX(UIFont.Small, txt)
        if st == "on" then
            self:drawRect(bx2, by2, cwid, chgt, 1, INK.r, INK.g, INK.b)
            self:drawText(txt, bx2 + (cwid - tw)/2, by2 + (chgt - fhS)/2, LCD.r, LCD.g, LCD.b, 1, UIFont.Small)
        else
            local a = (st == "free") and 0.78 or 0.17
            self:drawRectBorder(bx2, by2, cwid, chgt, a, INK.r, INK.g, INK.b)
            self:drawText(txt, bx2 + (cwid - tw)/2, by2 + (chgt - fhS)/2, INK.r, INK.g, INK.b, a, UIFont.Small)
        end
        -- ⚠️ La cellule n'agit QUE si une bank voisine existe. Elle délègue à `PSR.UI.actions`,
        --    donc le joueur marche jusqu'à la bank et l'action reste interruptible.
        if st ~= "none" then
            local target = self.dirIso and self.dirIso[cell.k]
            self:zone(bx2, by2, cwid, chgt, function(s)
                local isoSelf = s.pb and s.pb:getIsoObject()
                if not (isoSelf and target) then return end
                if st == "on" then PSR.UI.actions.unlinkOne(s.player, isoSelf, target)
                else               PSR.UI.actions.linkBank(s.player, isoSelf, target) end
                s.readAt = 0   -- relire dès la frame suivante : l'action peut aboutir vite
            end)
        end
    end
    ry = ry + (chgt + cg) * 3 + 4
    local leg = getText("IGUI_PSR_Bank_LinksLegend")
    self:drawText(leg, rx + (rw - tm:MeasureStringX(UIFont.NewSmall, leg))/2, ry,
                  INK.r, INK.g, INK.b, 0.62, UIFont.NewSmall)
    ry = ry + fhNS + 10
    self:etch(rx, ry, rw); ry = ry + 12

    self:label(getText("ContextMenu_PSR_Computer"), rx, ry + 2)
    -- « ? » quand la case de l'ordinateur n'est pas chargée : on distingue « il n'y en a pas »
    -- de « on ne peut pas savoir ». Les deux ne doivent pas s'écrire pareil.
    local ctxt = (self.compState == "yes" and getText("UI_Yes"))
              or (self.compState == "unknown" and "?")
              or getText("UI_No")
    self:pill(ctxt, rx + rw - 52, ry, self.compState == "yes")
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- PAGES DETAIL / DIAG
-- ═══════════════════════════════════════════════════════════════════════════════════════════
function PSRBankPanel:renderRows(lx, ly, lw, rows, title, after)
    local tm = getTextManager()
    local fhS, fhNS = tm:getFontHeight(UIFont.Small), tm:getFontHeight(UIFont.NewSmall)
    local x, y = lx + 18, ly + 14
    self:label(title, x, y); y = y + fhNS + 6
    self:etch(x, y, lw - 36); y = y + 12
    for _, r in ipairs(rows) do
        if r[1] == "" then
            y = y + 6; self:etch(x, y, lw - 36); y = y + 12
        else
            self:label(r[1], x, y + 1)
            self:valueRight(r[2], x + lw - 36, y)
            y = y + fhS + 6
        end
    end
    if after then after(self, x, y + 10) end
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- OUTILS DE LA PAGE DIAG — repris de l'ancien onglet « Debug »
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 🔴 J'ALLAIS SUPPRIMER `PSRStatusWindowDebugView.lua` EN CROYANT NE PERDRE QUE DU DEBUG.
--    Relecture avant suppression : **`Troubleshoot` n'était PAS derrière `getDebug()`** — il est
--    offert à TOUS les joueurs, avec l'infobulle « Use after bugfix updates if you're having
--    issues ». C'est un outil de SUPPORT, celui qu'on leur recommande quand un correctif est
--    publié. Le perdre aurait retiré une fonction sans que rien ne le signale.
-- 📌 Forme : **le nom d'un fichier n'est pas l'inventaire de son contenu.** « DebugView » m'avait
--    fait conclure « tout est du debug ». Écart *identifiant → identité*, appliqué à un fichier.
--    ⇒ avant de retirer un fichier, en lire le contenu, pas son nom.
function PSRBankPanel:renderDiagTools(x, y)
    local now = getTimestampMs()
    -- Anti-répétition : l'original bloquait le bouton 5 s après usage (`troubleshoot` déclenche
    -- un travail serveur). Horloge réelle, pas un compteur de frames comme l'original.
    local ready = (self.troubleshootAt or 0) <= now
    local w = self:lcdButton(getText("IGUI_PSR_Bank_Troubleshoot"), x, y, function(s)
        local pb = s.pb
        if not pb then return end
        PSR.PBSystem_Client:sendCommand(getSpecificPlayer(s.player), "troubleshoot",
                                        { x = pb.x, y = pb.y, z = pb.z })
        s.troubleshootAt = getTimestampMs() + 5000
        s.readAt = 0
    end, ready)

    -- Ces deux-là ÉTAIENT derrière `getDebug()` dans l'original : on garde exactement la même
    -- porte, ni plus ouverte ni plus fermée.
    if getDebug() then
        local pb = self.pb
        local w2 = self:lcdButton("Update Container Items", x + w + 10, y, function(s)
            if not s.pb then return end
            PSR.PBSystem_Client:sendCommand(getSpecificPlayer(s.player), "countBatteries",
                                            { x = s.pb.x, y = s.pb.y, z = s.pb.z })
            s.readAt = 0
        end, pb ~= nil)

        -- « Connect Backup Generator » : mêmes conditions que l'original — un générateur sur la
        -- case du JOUEUR, branché, et qui ne soit pas une bank.
        local chr = getSpecificPlayer(self.player)
        local sq  = chr and chr:getSquare()
        local gen = sq and sq:getGenerator()
        local can = gen and gen:isConnected() and not PSR.WorldUtil.findTypeOnSquare(sq, "PowerBank")
        self:lcdButton("Connect Backup Generator", x + w + 10 + w2 + 10, y, function(s)
            if not (gen and s.pb) then return end
            PSR.PBSystem_Client:sendCommand(getSpecificPlayer(s.player), "plugGenerator", {
                pbList = { { x = s.pb.x, y = s.pb.y, z = s.pb.z } },
                gen    = { x = gen:getX(), y = gen:getY(), z = gen:getZ() },
                plug   = true })
            s.readAt = 0
        end, can and true or false)
    end
end

function PSRBankPanel:detailRows()
    local pb = self.pb
    local gen = pb and pb.conGenerator
    return {
        { getText("IGUI_PSRWindow_Details_MaxCapacity"),     math.floor(self.capacity) .. " Ah" },
        { getText("IGUI_PSRWindow_Details_ConnectedPanels"), tostring(self.npanels) },
        { getText("IGUI_PSRWindow_Details_MaxPanelOutput"),  string.format("%.1f Ah", self.solarMax) },
        { getText("IGUI_PSRWindow_Details_BatteryDrain"),    string.format("%g Ah", math.floor(self.drain * 10 + 0.5) / 10) },
        { "", "" },
        { getText("IGUI_PSRWindow_Details_CoveredByMains"),
          (pb and pb.coveredByMains and pb:coveredByMains()) and getText("UI_Yes") or getText("UI_No") },
        { getText("IGUI_PSRWindow_Details_conGenerator"),    gen and getText("UI_Yes") or getText("UI_No") },
        -- `E-1` (2026-08-23) — ENGAGEMENT PUBLIC PRIS LE 15/08 auprès de `gropag` :
        --   « maybe you can add something like "BG is ACTIVE/INACTIVE" in main screen? »
        -- ⚖️ RECADRÉ PAR LE COMMANDEUR, et c'est ce recadrage qui rend la ligne utile :
        --   *« si le générateur de secours est actif, on l'entend déjà de base »*. Vrai —
        --   afficher « il tourne » serait redondant, et en plus FAUX jusqu'à une heure
        --   (`updateConGenerator` sort sur `if self.lastHour == currentHour then return end`).
        -- 🎯 Ce qu'on N'ENTEND PAS, c'est POURQUOI il tourne. `byFailsafe` n'est posé que
        --   quand c'est NOUS qui l'avons démarré, batterie vide (`PowerBankObject_Server:1893`,
        --   « c'est NOUS : on s'engage à l'éteindre »). Un joueur qui rentre chez lui apprend
        --   ainsi que son solaire est sous-dimensionné et qu'il brûle du carburant sans le savoir.
        -- ⚠️ La ligne dit donc « le failsafe a pris le relais », PAS « il tourne » : un générateur
        --   démarré À LA MAIN laisse `byFailsafe` nil et affiche No, ce qui est correct.
        --   *Un libellé qui promettrait « running » mentirait sur ce cas-là.*
        -- 📐 Zéro coût de données : `conGenerator` est déjà dans `savedObjectModData`, donc la
        --   table entière (dont `byFailsafe`) traverse déjà vers le client — aucun champ neuf,
        --   aucun changement de format de modData.
        { getText("IGUI_PSRWindow_Details_FailsafeActive"),
          (gen and gen.byFailsafe) and getText("UI_Yes") or getText("UI_No") },
        { "", "" },
        { getText("IGUI_PSRWindow_Details_NetworkCapacity"), math.floor(self.netCapacity) .. " Ah" },
        { getText("IGUI_PSRWindow_Details_NetworkPanels"),   tostring(self.netPanels) },
    }
end

function PSRBankPanel:diagRows()
    local gen = self.pb and self.pb.conGenerator
    return {
        -- 📌 CES TROIS LIBELLÉS RESTENT EN ANGLAIS, VOLONTAIREMENT. La page DIAG sert à produire
        --    un rapport de bug lisible par nous : une capture d'écran d'un joueur russe ou
        --    thaïlandais doit dire la même chose que la nôtre. *Traduire un diagnostic, c'est
        --    rendre illisible la seule information qu'on demande au joueur de nous transmettre.*
        --    Les VALEURS de « Context » (single player / coop host / dedicated client) suivent la
        --    même règle, et pour la même raison — c'est la leçon PSR v1.60.
        { "Bank position", string.format("%d, %d, %d", self.bx, self.by, self.bz) },
        { "Powered",       self.isOn and getText("UI_Yes") or getText("UI_No") },
        { "", "" },
        { getText("IGUI_PSRWindow_Details_Failsafe"),
          (gen and PSR.WorldUtil.findOnSquare(getSquare(gen.x, gen.y, gen.z), "solarmod_tileset_01_15"))
            and getText("UI_Yes") or getText("UI_No") },
        { getText("IGUI_PSRWindow_Details_conGenerator"),
          gen and string.format("%d, %d, %d", gen.x, gen.y, gen.z) or getText("UI_No") },
        { "", "" },
        -- Contexte réseau : la leçon PSR v1.60 — « validé en jeu » sans nommer le contexte est un
        -- verdict FAUX. L'afficher rend tout rapport de joueur exploitable du premier coup.
        --
        -- 🔴 DÉDUCTION REMPLACÉE PAR UNE LECTURE DIRECTE (2026-08-07). Je déduisais le contexte de
        --    `isServer()`/`isClient()` — or **`isCoopHost()` existe** (📚 doc lue le 2026-08-07,
        --    `LuaManager.GlobalObject` : `static boolean isCoopHost()`), et une déduction à partir
        --    de deux drapeaux ne vaut jamais le drapeau qui répond à la question.
        -- ⚠️ `type(...) == "function"` : si un build ne l'exposait pas, l'appel direct tuerait le
        --    fichier au chargement. Une ligne de diagnostic ne doit jamais pouvoir faire ça.
        { "Context", (type(isCoopHost) == "function" and isCoopHost() and "coop host")
                     or (isServer() and not isClient() and "server")
                     or (isClient() and "dedicated client")
                     or "single player" },
        -- 🔬 DRAPEAUX BRUTS. Ajoutés parce que deux observations se contredisaient en test :
        --    la boussole agissait (donc les systèmes serveur étaient joignables) alors que le
        --    contexte s'affichait « dedicated client » et que la déliaison de l'ordinateur ne
        --    faisait rien — or les deux passent par la même garde `PSR.PBSystem_Server`.
        -- 🔑 **Quand deux mesures s'excluent, on n'arbitre pas : on instrumente.** `SRV` est LE
        --    discriminant — c'est cette table-là que quatre TimedActions interrogent pour décider
        --    d'agir ou de sortir. La déduire des autres drapeaux serait refaire l'erreur.
        { "", "" },
        { "Flags CL/SV/CH/MP", string.format("%s %s %s %s",
              isClient() and "1" or "0",
              isServer() and "1" or "0",
              (type(isCoopHost) == "function" and isCoopHost()) and "1" or "0",
              (type(isMultiplayer) == "function" and isMultiplayer()) and "1" or "0") },
        { "Server systems (SRV)", PSR.PBSystem_Server and "present" or "absent" },
    }
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- RENDU
-- ═══════════════════════════════════════════════════════════════════════════════════════════
function PSRBankPanel:render()
    self.zones = {}
    local W, H = self:getWidth(), self:getHeight()
    local tm   = getTextManager()
    local fhNS = tm:getFontHeight(UIFont.NewSmall)

    -- Hauteur du bandeau DÉDUITE de la police, jamais choisie : une valeur en dur redeviendrait
    -- fausse au premier joueur qui change sa taille de police.
    local keyH  = fhNS + 16
    local bandH = 10 + keyH + 9 + keyH + 9 + fhNS + 10

    self:drawRect(0, 0, W, H, 1, BEZEL.r, BEZEL.g, BEZEL.b)

    local lx, ly = PAD, PAD
    local lw, lh = W - PAD * 2, H - PAD * 2 - 10 - bandH
    self:drawRect(lx, ly, lw, lh, 1, LCD.r, LCD.g, LCD.b)
    self:drawRect(lx, ly, lw, lh * 0.42, 0.45, LCD_HI.r, LCD_HI.g, LCD_HI.b)
    self:drawRectBorder(lx, ly, lw, lh, 1, 0.04, 0.05, 0.06)

    if not self.ok then
        local msg = getText("IGUI_PSRComputerPanel_Loading")
        self:drawText(msg, lx + (lw - tm:MeasureStringX(UIFont.Medium, msg)) / 2, ly + lh / 2 - 8,
                      INK.r, INK.g, INK.b, 0.8, UIFont.Medium)
    elseif self.page == "MAIN" then
        local splitX = lx + math.floor(lw * 0.535)
        self:vetch(splitX, ly + 6, lh - 12)
        self:renderMain(lx, ly, lw, lh, splitX)
    elseif self.page == "DETAIL" then
        self:renderRows(lx, ly, lw, self:detailRows(), getText("IGUI_PSRWindow_Details_TabTitle"))
    else
        self:renderRows(lx, ly, lw, self:diagRows(), getText("IGUI_PSR_Bank_Diagnostics"),
                        PSRBankPanel.renderDiagTools)
    end

    -- ── Bandeau de touches ─────────────────────────────────────────────────────────────────
    local by = H - PAD - bandH
    self:drawRect(PAD, by, lw, bandH, 1, SILVER.r, SILVER.g, SILVER.b)
    self:drawRect(PAD, by, lw, bandH * 0.45, 0.22, 1, 1, 1)

    local kL, kR = PAD + 12, PAD + lw - 12       -- bords utiles du bandeau
    local ky = by + 10
    local GAP = 8

    -- ── Rangée 1 : pages à gauche, actions à droite ────────────────────────────────────────
    -- Les trois touches de page prennent la MÊME largeur, celle du plus long des trois libellés :
    -- des onglets de tailles inégales se lisent comme un défaut d'alignement, pas comme un choix.
    local pageW = 0
    for _, p in ipairs({ "MAIN", "DETAIL", "DIAG" }) do
        pageW = math.max(pageW, self:keyWidth(p, 76))
    end
    local kx = kL
    for _, p in ipairs({ "MAIN", "DETAIL", "DIAG" }) do
        self:key(p, kx, ky, pageW, keyH, self.page == p and "lit" or "idle", function(s) s.page = p end)
        kx = kx + pageW + GAP
    end

    -- Posées de DROITE à GAUCHE : c'est le bord droit qui est fixe, pas leur largeur.
    local txtOn    = self.isOn and getText("ContextMenu_Turn_Off") or getText("ContextMenu_Turn_On")
    local txtUnAll = getText("ContextMenu_PSR_UnlinkAll")
    local wUnAll   = self:keyWidth(txtUnAll)
    local wOn      = self:keyWidth(txtOn)
    self:key(txtUnAll, kR - wUnAll, ky, wUnAll, keyH,
             -- Même règle que l'ancien menu : au-dessous de 2 liens directs, « tout délier » fait
             -- doublon avec un clic sur la boussole, donc l'entrée n'existait pas.
             (self.directLinks or 0) > 1 and "idle" or "off", function(s)
                 local iso = s.pb and s.pb:getIsoObject()
                 if iso then PSR.UI.actions.unlinkAll(s.player, iso) end
                 s.readAt = 0
             end)
    -- Marche / arrêt de la bank. `activatePowerbank` porte la garde 2026-08-04 (bank ramassée
    -- entre l'ouverture du menu et le clic) — on l'appelle, on ne la refait pas.
    self:key(txtOn, kR - wUnAll - GAP - wOn, ky, wOn, keyH, self.ok and "idle" or "off", function(s)
                 local iso = s.pb and s.pb:getIsoObject()
                 if iso then PSR.UI.actions.activatePowerbank(s.player, iso, not s.isOn) end
                 s.readAt = 0
             end)

    -- ── Rangée 2 : « Connect panels » prend ce qui reste ────────────────────────────────────
    ky = ky + keyH + 9
    local wClose = self:keyWidth(getText("IGUI_PSRComputerPanel_Close"), 100)
    local wComp  = self:keyWidth(getText("ContextMenu_PSR_DisconnectComputerFromBank"))
    -- ⚠️ Garde de dernier recours : si les libellés traduits mangeaient toute la rangée, la touche
    --    souple deviendrait négative et disparaîtrait. On lui garantit un minimum, quitte à ce que
    --    la rangée déborde légèrement — un débordement se voit et se corrige ; une touche absente
    --    ne se signale pas.
    local connW = math.max(140, (kR - kL) - wClose - wComp - GAP * 2)
    self:key(getText("ContextMenu_PSR_ConnectPanels"), kL, ky, connW, keyH, "idle", function(s)
        local iso = s.pb and s.pb:getIsoObject()
        local sq  = iso and iso:getSquare()
        if sq then
            -- Le curseur prend le contrôle de la souris : garder le panneau ouvert par-dessus
            -- placerait ses zones de clic entre le joueur et sa cible. On ferme.
            s:close()
            PSR.UI.actions.connectPanelCursor(s.player, sq, iso)
        end
    end)
    self:key(getText("ContextMenu_PSR_DisconnectComputerFromBank"),
             kL + connW + GAP, ky, wComp, keyH,
             -- 🔴 CETTE TOUCHE ÉTAIT GRISÉE SUR « ordinateur trouvé », ce qui l'aurait fait
             --    disparaître EXACTEMENT quand elle sert. C'est l'issue de secours ajoutée pour
             --    le signal Zephyrum (v1.60) : quand l'ordinateur a été démonté, l'entrée reste
             --    sur la bank et **plus rien d'autre ne peut l'effacer** — la bank refusait alors
             --    silencieusement tout nouvel ordinateur, définitivement.
             -- 🔑 Elle est donc conditionnée à la COORDONNÉE portée par la bank, jamais à la
             --    présence vérifiée de l'objet. *Une issue de secours ne se ferme pas sur
             --    l'absence de ce dont elle répare l'absence.*
             self.compCoord and "idle" or "off", function(s)
                 local iso = s.pb and s.pb:getIsoObject()
                 if iso and s.compCoord then
                     PSR.UI.actions.unlinkComputerFromBank(s.player, iso, s.compCoord)
                 end
                 s.readAt = 0
             end)
    self:key(getText("IGUI_PSRComputerPanel_Close"), kR - wClose, ky, wClose, keyH,
             "idle", function(s) s:close() end)

    -- ── Sérigraphie + LEDs ─────────────────────────────────────────────────────────────────
    ky = ky + keyH + 9
    local lex = PAD + 12
    local function led(on, r, g, b)
        self:drawRect(lex, ky + 3, 8, 8, on and 1 or 0.35, r, g, b)
        self:drawRectBorder(lex, ky + 3, 8, 8, 0.45, 0, 0, 0)
        lex = lex + 13
    end
    led((self.solarNow or 0) > 0, GREEN.r, GREEN.g, GREEN.b)      -- soleil
    led((self.net or 0) > 0,      AMBER.r, AMBER.g, AMBER.b)      -- en charge
    -- 🔴 CORRIGÉ 2026-08-16 — cette LED était allumée EN PERMANENCE.
    --    `conGenerator` ne vaut jamais `nil` quand il n'y a pas de secours : il vaut **`false`**
    --    (`initNew`, `disconnectBackupGenerator`, `autoConnectBackup`). Le test `~= nil` était donc
    --    toujours vrai. Deux surfaces du même écran se contredisaient : la ligne « Details » disait
    --    `No` (elle, correctement) pendant que la LED disait « raccordé ».
    -- 🔑 *Un voyant qui ne s'éteint jamais n'est pas un voyant, c'est une décoration* — et c'est
    --    précisément ce que `DarkOutX` a lu comme une contradiction du mod (signal du 15/08).
    led(self.pb and self.pb.conGenerator and true or false, 0.85, 0.35, 0.30) -- secours raccordé

    local brand = "PLYSKEN SOLAR REVOLUTION"
    local bw = tm:MeasureStringX(UIFont.NewSmall, brand) + (#brand - 1) * TRACK
    self:spaced(brand, PAD + (lw - bw) / 2, ky, 0.17, 0.18, 0.20, 1, UIFont.NewSmall)
end

-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Cycle de vie
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 🔑 DEUX GARDES QUE L'ANCIENNE FENÊTRE N'AVAIT PAS. Vérifié en la relisant en entier le
--    2026-08-07 : `PSRStatusWindow` n'avait AUCUNE horloge — ni proximité, ni objet disparu
--    (seul son `render` fermait sur `getIsoObject()` nil). Ma note de recherche affirmait
--    l'inverse ; c'était faux, et le panneau devait donc les AJOUTER, pas les hériter.
-- ⚠️ Hystérésis volontaire : on n'ouvre qu'à portée, mais on ne ferme qu'à 5 cases. Avec un
--    seuil unique, un pas de côté au bord ferait clignoter le panneau (leçon PWS).
PSRBankPanel.CLOSE_RANGE = 5

function PSRBankPanel:update()
    ISPanel.update(self)
    local now = getTimestampMs()

    self.proximityAt = self.proximityAt or 0
    if now >= self.proximityAt then
        self.proximityAt = now + 500
        local chr = getSpecificPlayer(self.player)
        local sq  = getSquare(self.bx, self.by, self.bz)
        -- ⚠️ Case non chargée = on NE SAIT PAS. On ne ferme rien sur une absence d'information :
        --    c'est la règle qui évite de fermer la fenêtre d'un joueur dont le chunk se recharge.
        if not chr then self:close(); return end
        if sq and not PSR.WorldUtil.findTypeOnSquare(sq, "PowerBank") then self:close(); return end
        local dx, dy = math.abs(chr:getX() - self.bx), math.abs(chr:getY() - self.by)
        if math.floor(chr:getZ()) ~= self.bz or math.max(dx, dy) > PSRBankPanel.CLOSE_RANGE then
            self:close(); return
        end
    end

    self.readAt = self.readAt or 0
    if now >= self.readAt then self:refresh() end
end

function PSRBankPanel:close()
    self:setVisible(false)
    self:removeFromUIManager()
    PSRBankPanel.instance = nil
end

function PSRBankPanel:new(x, y, w, h)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self); self.__index = self
    o.moveWithMouse   = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor     = { r = 0, g = 0, b = 0, a = 0 }
    o.page   = "MAIN"
    o.zones  = {}
    o.ok     = false
    o.readAt = 0
    return o
end

function PSRBankPanel.OnOpenPanel(player, square)
    if not square then return end
    if PSRBankPanel.instance then PSRBankPanel.instance:close() end
    local w, h = 860, 600
    local p = PSRBankPanel:new((getCore():getScreenWidth()  - w) / 2,
                               (getCore():getScreenHeight() - h) / 2, w, h)
    p.player = player
    p.bx, p.by, p.bz = square:getX(), square:getY(), square:getZ()
    p:initialise()
    p:addToUIManager()
    p:refresh()          -- lecture immédiate : sinon le premier dixième de seconde affiche « ... »
    PSRBankPanel.instance = p
    return p
end

PSR.BankPanel = PSRBankPanel
