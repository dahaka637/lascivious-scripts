-- Lascivious Factions System - faction upgrades ("Aprimoramentos da Facção").
--
-- A faction earns one upgrade point every time its live power (FF.factionScore)
-- crosses a milestone; the owner spends points levelling up the tracks in
-- FF.UPGRADE_TYPES. This file only holds the data model and the pure milestone/
-- catalog math -- exactly the split LFS_Shared already uses for claim-size math --
-- so the server (award/spend) and the client (panel display) read the identical
-- numbers. No IO, no localization calls (FF.text lives in the client-only
-- LFS_Localization) -- safe to require from server, client or shared context.
--
-- Effects are implemented by their owning subsystems (territory wellbeing,
-- workshop, Shop commerce/bounty, treasury, hunter and legacy). This file deliberately
-- remains the shared data/catalog layer; server/client implementations consume it.

require "LFS_Shared"

local FF = LasciviousFactionsSystem

-- ---------------------------------------------------------------------------
-- Milestones
-- ---------------------------------------------------------------------------
-- Faction-power thresholds that each grant one upgrade point the first time a
-- faction's live score reaches them. Hand-picked for the early game; a faction
-- that outgrows the list keeps earning points via MILESTONE_TAIL_STEP, which
-- repeats the final gap indefinitely rather than capping progression.
local MILESTONES = { 100, 200, 350, 500, 700, 900, 1200, 1500 }
local MILESTONE_TAIL_STEP = MILESTONES[#MILESTONES] - MILESTONES[#MILESTONES - 1]

-- The n-th milestone (1-indexed), extended past the hardcoded list by repeating
-- the last gap. Pure -- safe to call from client UI every frame.
function FF.upgradeMilestoneAt(n)
    n = math.max(1, math.floor(tonumber(n) or 1))
    if n <= #MILESTONES then return MILESTONES[n] end
    return MILESTONES[#MILESTONES] + MILESTONE_TAIL_STEP * (n - #MILESTONES)
end

-- ---------------------------------------------------------------------------
-- Upgrade catalog
-- ---------------------------------------------------------------------------
-- Data-driven, like LasciviousShop_Catalog: a new upgrade is a new entry here
-- (plus its actual level effect in the owning subsystem) -- nothing else here or the
-- panel needs to change to show it. `key` is the stable id stored under
-- faction.upgrades.levels; labelKey/descTiers are FF.text() keys the CLIENT
-- resolves at display time. `implemented` (default falsy) is read by
-- LFS_Panel.lua's populateUpgrades to decide whether a card still shows the
-- "(em desenvolvimento)" badge -- set it once an upgrade's actual effect ships.
--
-- descTiers replaces a single static descKey/descFallback (2026-08-21, explicit
-- ask -- "quero... o texto mudar de acordo com o nível"): 5 entries, one per
-- FF.upgradeTier() bucket (0 / 1-3 / 4-6 / 7-9 / 10), so the card's description
-- itself narrates where the faction currently stands instead of reading like a
-- static changelog/formula sheet at every level. Written deliberately plain --
-- short sentences, contractions, no "Concede/Intensifica/Revela"-style
-- corporate-manual phrasing -- per explicit ask ("menos cara de IA").
--
-- IMPORTANT: Lua fallbacks below use a literal single "%". Translation JSON is
-- different: getText passes it through Java Formatter even with no replacement
-- arguments, so literal percent signs there MUST be escaped as "%%".
FF.UPGRADE_TYPES = {
    {
        key = "wellbeing", maxLevel = 10, implemented = true,
        labelKey = "UI_LFS_UpgradeWellbeingName", labelFallback = "Bem-estar",
        descTiers = {
            { key = "UI_LFS_UpgradeWellbeingDescT1", fallback =
                "Sem nenhum aprimoramento aqui, o território não oferece conforto extra -- só o abrigo em si." },
            { key = "UI_LFS_UpgradeWellbeingDescT2", fallback =
                "Os primeiros cuidados já fazem diferença: feridas fecham um pouco mais rápido e o humor "
                .. "melhora de leve pra quem está em casa." },
            { key = "UI_LFS_UpgradeWellbeingDescT3", fallback =
                "A base já cuida bem de quem mora nela -- cura, humor e fadiga se recuperam visivelmente "
                .. "mais rápido dentro do território." },
            { key = "UI_LFS_UpgradeWellbeingDescT4", fallback =
                "Quase no limite: a recuperação já é rápida de verdade, e até fome e sede começam a "
                .. "segurar um pouco mais." },
            { key = "UI_LFS_UpgradeWellbeingDescT5", fallback =
                "No auge, a base é um verdadeiro santuário: cura forte, humor estável, fadiga sumindo "
                .. "rápido, e fome e sede que quase esperam por você." },
        },
        technicalKey = "UI_LFS_UpgradeWellbeingTechnical", technicalFallback =
            "(Com o tempo, melhora sua cura, cicatrização, humor e fadiga dentro do território; reduz "
            .. "levemente a queda de fome e sede.)",
    },
    {
        key = "workshop", maxLevel = 10, implemented = true,
        labelKey = "UI_LFS_UpgradeWorkshopName", labelFallback = "Oficina",
        descTiers = {
            { key = "UI_LFS_UpgradeWorkshopDescT1", fallback =
                "Nenhum veículo protegido se conserta sozinho -- ainda depende só de peças e trabalho manual." },
            { key = "UI_LFS_UpgradeWorkshopDescT2", fallback =
                "Os primeiros reparos automáticos já rodam devagar nos veículos protegidos, até um teto "
                .. "ainda modesto." },
            { key = "UI_LFS_UpgradeWorkshopDescT3", fallback =
                "A oficina já mantém a frota rodando de verdade -- peças se recuperam sozinhas, teto de "
                .. "reparo maior, e a bateria começa a carregar sozinha." },
            { key = "UI_LFS_UpgradeWorkshopDescT4", fallback =
                "A bateria já recarrega sozinha e a frota praticamente se cuida -- só falta um detalhe "
                .. "pro pacote ficar completo." },
            { key = "UI_LFS_UpgradeWorkshopDescT5", fallback =
                "Oficina completa: peças e bateria se recuperando o tempo todo, e um fiozinho de "
                .. "combustível aparece no tanque enquanto o veículo descansa protegido." },
        },
        technicalKey = "UI_LFS_UpgradeWorkshopTechnical", technicalFallback =
            "(Veículos protegidos dentro do território são reparados automaticamente -- o teto de reparo "
            .. "sobe 10% por nível; a partir do nível 5 a bateria também recarrega aos poucos, e no nível "
            .. "máximo até combustível é adicionado ao tanque com o tempo.)",
    },
    {
        key = "commerce", maxLevel = 10, implemented = true,
        labelKey = "UI_LFS_UpgradeCommerceName", labelFallback = "Comércio",
        descTiers = {
            { key = "UI_LFS_UpgradeCommerceDescT1", fallback =
                "Preço cheio pra todo mundo -- a facção ainda não negocia nada melhor na loja." },
            { key = "UI_LFS_UpgradeCommerceDescT2", fallback =
                "Já dá pra notar no bolso: um desconto pequeno na loja pra quem é da facção." },
            { key = "UI_LFS_UpgradeCommerceDescT3", fallback =
                "Comprar como membro já compensa de verdade, com um desconto bem relevante garantido." },
            { key = "UI_LFS_UpgradeCommerceDescT4", fallback =
                "O desconto já pesa bastante na hora de comprar -- quase preço de atacado." },
            { key = "UI_LFS_UpgradeCommerceDescT5", fallback =
                "No nível máximo a facção compra praticamente no atacado -- 50% de desconto em tudo na loja." },
        },
        technicalKey = "UI_LFS_UpgradeCommerceTechnical", technicalFallback =
            "(Desconto por nível na loja: Nv.1 3%, Nv.2 6%, Nv.3 10%, Nv.4 14%, Nv.5 19%, "
            .. "Nv.6 24%, Nv.7 30%, Nv.8 36%, Nv.9 43%, Nv.10 50%.)",
    },
    {
        -- key intentionally left as "combatBounty" (not renamed alongside
        -- the display label) -- it's the internal identifier
        -- FF.upgradeLevel/faction.upgrades.levels actually store progress
        -- under; renaming it would orphan any level a live faction already
        -- invested here. Only the user-facing label/description changed.
        key = "combatBounty", maxLevel = 10, implemented = true,
        labelKey = "UI_LFS_UpgradeCombatBountyName", labelFallback = "Multiplicador de Recompensa",
        descTiers = {
            { key = "UI_LFS_UpgradeCombatBountyDescT1", fallback =
                "Abater zumbi e sobreviver rendem só o crédito de sempre, sem nenhum bônus." },
            { key = "UI_LFS_UpgradeCombatBountyDescT2", fallback =
                "Já compensa se arriscar: um bônus pequeno em cima de cada abate e de cada hora sobrevivida." },
            { key = "UI_LFS_UpgradeCombatBountyDescT3", fallback =
                "A facção recompensa bem quem enfrenta o perigo -- abates e sobrevivência rendem "
                .. "consideravelmente mais crédito." },
            { key = "UI_LFS_UpgradeCombatBountyDescT4", fallback =
                "Cada abate e cada hora viva já valem quase o dobro -- sobreviver aqui está ficando muito "
                .. "lucrativo." },
            { key = "UI_LFS_UpgradeCombatBountyDescT5", fallback =
                "No topo, cada zumbi abatido vale até 2.5x o crédito normal, e cada hora viva rende até "
                .. "1.5x -- aqui, sobreviver é o negócio mais lucrativo que tem." },
        },
        technicalKey = "UI_LFS_UpgradeCombatBountyTechnical", technicalFallback =
            "(Multiplica os créditos por zumbi abatido -- até 2.5x no nível máximo -- e por hora "
            .. "sobrevivida -- até 1.5x no nível máximo.)",
    },
    {
        key = "treasury", maxLevel = 10, implemented = true,
        labelKey = "UI_LFS_UpgradeTreasuryName", labelFallback = "Tesouraria",
        descTiers = {
            { key = "UI_LFS_UpgradeTreasuryDescT1", fallback =
                "O cofre da facção só guarda crédito -- parado, sem render nada." },
            { key = "UI_LFS_UpgradeTreasuryDescT2", fallback =
                "Um juro pequeno já cai todo dia sobre o saldo guardado, quase imperceptível mas real." },
            { key = "UI_LFS_UpgradeTreasuryDescT3", fallback =
                "O dinheiro parado já trabalha sozinho, rendendo um extra digno de nota todo dia." },
            { key = "UI_LFS_UpgradeTreasuryDescT4", fallback =
                "O cofre já rende um extra considerável todo dia -- quase perto do máximo que ele pode dar." },
            { key = "UI_LFS_UpgradeTreasuryDescT5", fallback =
                "No nível máximo o cofre rende 1% ao dia -- deixar crédito guardado virou uma estratégia "
                .. "por si só." },
        },
        technicalKey = "UI_LFS_UpgradeTreasuryTechnical", technicalFallback =
            "(O saldo da facção rende juros diários -- 0.1% por nível, até 1% ao dia no nível máximo.)",
    },
    {
        key = "hunter", maxLevel = 10, implemented = true,
        labelKey = "UI_LFS_UpgradeHunterName", labelFallback = "Caçador",
        descTiers = {
            { key = "UI_LFS_UpgradeHunterDescT1", fallback =
                "A facção não enxerga além do próprio território -- quem está lá fora, fica invisível." },
            { key = "UI_LFS_UpgradeHunterDescT2", fallback =
                "Um primeiro alcance de vigia: dá pra notar sombras de gente estranha rondando perto das "
                .. "fronteiras." },
            { key = "UI_LFS_UpgradeHunterDescT3", fallback =
                "Os olheiros já cobrem uma boa distância -- o mapa passa a marcar áreas onde intrusos "
                .. "podem estar escondidos." },
            { key = "UI_LFS_UpgradeHunterDescT4", fallback =
                "A vigilância já cobre uma área enorme, quase alcançando seu limite máximo." },
            { key = "UI_LFS_UpgradeHunterDescT5", fallback =
                "No auge, a facção enxerga longe e enxerga certo -- inclusive o nome de quem estiver "
                .. "espreitando por perto." },
        },
        technicalKey = "UI_LFS_UpgradeHunterTechnical", technicalFallback =
            "(Mostra no mapa de Território uma área aproximada onde jogadores de fora da facção podem "
            .. "estar, até 1500 tiles de distância no nível máximo; quanto mais perto do território, "
            .. "menor e mais precisa a área; no nível máximo também revela o nome do alvo.)",
    },
    {
        key = "legacy", maxLevel = 10, implemented = true,
        labelKey = "UI_LFS_UpgradeLegacyName", labelFallback = "Legado",
        descTiers = {
            { key = "UI_LFS_UpgradeLegacyDescT1", fallback =
                "Sem Legado, cada morte encerra a experiência daquele personagem por completo." },
            { key = "UI_LFS_UpgradeLegacyDescT2", fallback =
                "A facção já preserva um pouco do treino dos seus mortos: o próximo personagem nasce "
                .. "com alguns pontos extras e recupera uma parte pequena do XP perdido." },
            { key = "UI_LFS_UpgradeLegacyDescT3", fallback =
                "O conhecimento da facção já sobrevive bem à morte -- o próximo personagem volta com "
                .. "um reforço sólido de criação e boa parte do XP bruto herdado." },
            { key = "UI_LFS_UpgradeLegacyDescT4", fallback =
                "O Legado está forte: morrer ainda dói, mas quase todo o treino acumulado encontra um "
                .. "caminho de volta no próximo personagem." },
            { key = "UI_LFS_UpgradeLegacyDescT5", fallback =
                "No auge, a facção transforma experiência em memória viva: o próximo personagem recebe "
                .. "20 pontos extras de criação e até 100% do XP bruto preservado." },
        },
        technicalKey = "UI_LFS_UpgradeLegacyTechnical", technicalFallback =
            "(Ao morrer como membro de uma facção ativa, registra uma herança para o próximo personagem: "
            .. "+2 pontos de criação e 10% do XP bruto preservado por nível.)",
    },
}

local TYPE_BY_KEY = {}
for _, def in ipairs(FF.UPGRADE_TYPES) do TYPE_BY_KEY[def.key] = def end

function FF.upgradeTypeDef(key)
    return key and TYPE_BY_KEY[key] or nil
end

-- Which of the 5 descTiers entries applies at this level: 1 = not started (0),
-- 2 = early (1-3), 3 = established (4-6), 4 = advanced (7-9), 5 = MAXED (10
-- exactly, its own dedicated bucket -- explicit ask: "no nível 10
-- especificamente precisa ser um [texto] diferente só para ele", not shared
-- with 7-9 the way the old 4-bucket split lumped 8-10 together). Pure, so
-- both the panel and anything else that wants to describe a level can share
-- one definition of the buckets.
function FF.upgradeTier(level)
    level = math.max(0, math.floor(tonumber(level) or 0))
    if level <= 0 then return 1
    elseif level <= 3 then return 2
    elseif level <= 6 then return 3
    elseif level <= 9 then return 4
    else return 5 end
end

function FF.legacyLevel(level)
    level = tonumber(level) or 0
    if level ~= level or level == math.huge or level == -math.huge then level = 0 end
    return math.max(0, math.min(10, math.floor(level)))
end

function FF.legacyCreationPoints(level)
    return FF.legacyLevel(level) * 2
end

function FF.legacyXpRetention(level)
    return math.max(0, math.min(1, FF.legacyLevel(level) * 0.10))
end

-- ---------------------------------------------------------------------------
-- Faction data
-- ---------------------------------------------------------------------------
-- Migration entry point, same idiom as FF.ensureTribute/FF.ensureStats. `levels`
-- holds one integer per catalog key (absent/0 = not upgraded yet).
-- `milestonesClaimed` is a monotonic counter of how many thresholds have already
-- paid out -- comparing the CURRENT score against it (rather than storing a
-- "peak score") means a later dip (a member leaving, a death resetting their
-- score) can never claw back a point already earned. Idempotent -- safe to call
-- on every access.
function FF.ensureUpgrades(faction)
    if faction and type(faction.upgrades) ~= "table" then
        faction.upgrades = { points = 0, milestonesClaimed = 0, levels = {} }
    end
    if faction then
        local u = faction.upgrades
        local points = tonumber(u.points) or 0
        local claimed = tonumber(u.milestonesClaimed) or 0
        if points ~= points or points == math.huge or points == -math.huge then points = 0 end
        if claimed ~= claimed or claimed == math.huge or claimed == -math.huge then claimed = 0 end
        u.points = math.max(0, math.floor(points))
        u.milestonesClaimed = math.max(0, math.floor(claimed))
        if type(u.levels) ~= "table" then u.levels = {} end
        for _, def in ipairs(FF.UPGRADE_TYPES) do
            local level = tonumber(u.levels[def.key]) or 0
            if level ~= level or level == math.huge or level == -math.huge then level = 0 end
            u.levels[def.key] = math.max(0, math.min(def.maxLevel, math.floor(level)))
        end
    end
    return faction
end

function FF.upgradeLevel(faction, key)
    if not (faction and faction.upgrades and key) then return 0 end
    local levels = faction.upgrades.levels
    if type(levels) ~= "table" then return 0 end
    local level = tonumber(levels[key]) or 0
    if level ~= level or level == math.huge or level == -math.huge then return 0 end
    local def = FF.upgradeTypeDef(key)
    return math.max(0, math.min(def and def.maxLevel or level, math.floor(level)))
end

-- Does this faction currently have claimed territory? The hard prerequisite the
-- design calls for: every upgrade's effect requires this,
-- while points/levels are earned and spent independently of it -- losing your
-- claim pauses the payoff, it never costs you progress. See FF.UPGRADE_TYPES.
function FF.upgradesActive(faction)
    return faction ~= nil and FF.totalArea(faction.claims) > 0
end
