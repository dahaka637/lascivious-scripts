-- Aplica as opcoes escolhidas pelo dono do servidor no Sandbox Settings do
-- jogo (arquivo media/sandbox-options.txt, mesmo mecanismo do vanilla) por
-- cima dos valores padrao de HardcoreKits_Config.lua. Roda uma vez no boot,
-- nos dois lados -- SandboxVars e sincronizado do servidor pros clientes,
-- entao ambos leem o mesmo valor final (util pro RouletteSpeedMultiplier
-- etc, que sao lidos pelo lado cliente na hora de desenhar a roleta).
--
-- Depois que esta ponte roda, o "default" que realmente vale e o `default=`
-- escrito em sandbox-options.txt, nao mais o valor hardcoded em
-- HardcoreKits_Config.lua (que fica so como fallback de seguranca, usado
-- se por algum motivo SandboxVars.HardcoreKits nao existir ainda).
--
-- WelcomeMessageText, ModdedContentExcludeList e HardcoreKitsAdminOverrides
-- ficam DE FORA de proposito: o sistema de sandbox do jogo so tem tipos
-- boolean/integer/double/enum (nao tem "string"/texto livre), entao qualquer
-- coisa que precise de uma lista de fullTypes ou texto livre continua so
-- editavel a mao nesses arquivos.
require "HardcoreKits_Config"

HardcoreKitsSandboxBridge = HardcoreKitsSandboxBridge or {}

local function sandboxVars()
    return SandboxVars and SandboxVars.HardcoreKits
end

-- { <nome no sandbox-options.txt>, apply(valor) }
-- 2026-08-22: trimmed to only the values actually tuned in practice --
-- explicit request, an exhaustive "deixa só: ..." keep-list per page (same
-- sandbox-option-count reduction as the removals below and in LFS/Shop/
-- PhunZones). Every removed entry keeps working exactly as before with a
-- fixed value now instead of a sandbox-configurable one -- see the matching
-- HardcoreKits_Config.lua defaults (several were also given a NEW fixed
-- value per explicit request: InitialFirearmChance 50->100,
-- FoodDrinkMultiRollMode true->false, SurvivalCategoriesFullyRandom
-- false->true, MedicalKitRandomItemCountMax 3->5, FastRouletteMode
-- false->true, EnableAuditLog true->false).
local MAPPING = {
    -- ---------- Kit Inicial ----------
    { "InitialKitEnabled", function(v) HardcoreKitsConfig.InitialKitEnabled = v end },
    { "InitialKitSingleUseEnabled", function(v) HardcoreKitsConfig.InitialKitSingleUseEnabled = v end },
    { "InitialKitCooldownEnabled", function(v) HardcoreKitsConfig.InitialKitCooldownEnabled = v end },
    { "InitialKitCooldownHours", function(v) HardcoreKitsConfig.InitialKitCooldownRealHours = v end },
    { "InitialFoodQuantityMin", function(v) HardcoreKitsConfig.InitialFoodQuantityMin = v end },
    { "InitialFoodQuantityMax", function(v) HardcoreKitsConfig.InitialFoodQuantityMax = v end },
    { "InitialDrinkQuantityMin", function(v) HardcoreKitsConfig.InitialDrinkQuantityMin = v end },
    { "InitialDrinkQuantityMax", function(v) HardcoreKitsConfig.InitialDrinkQuantityMax = v end },
    { "InitialFirearmChance", function(v) HardcoreKitsConfig.InitialFirearmChance = v end },
    { "InitialAmmoBoxesMin", function(v) HardcoreKitsConfig.InitialAmmoBoxesMin = v end },
    { "InitialAmmoBoxesMax", function(v) HardcoreKitsConfig.InitialAmmoBoxesMax = v end },
    { "InitialMeleeHighDamageOnly", function(v) HardcoreKitsConfig.InitialMeleeHighDamageOnly = v end },
    { "InitialMeleeMinDamage", function(v) HardcoreKitsConfig.InitialMeleeMinDamage = v end },
    { "InitialResourceQuantityMin", function(v) HardcoreKitsConfig.InitialResourceQuantityMin = v end },
    { "InitialResourceQuantityMax", function(v) HardcoreKitsConfig.InitialResourceQuantityMax = v end },

    -- ---------- Recompensa de Sobrevivencia ----------
    -- SurvivalRewardEnabled NAO esta mapeado de proposito (2026-08-28): bug
    -- conhecido, fixo em false direto no Config.lua ate ser investigado com
    -- calma -- ver comentario la e em HardcoreKits_State.lua. Se mapeasse
    -- aqui, um admin poderia religar sem saber do problema.
    -- sandbox usa DIAS (mais amigavel pro dono do servidor); Config.lua guarda em horas
    { "SurvivalRewardIntervalDays", function(v) HardcoreKitsConfig.SurvivalRewardIntervalHours = v * 24 end },
    { "SurvivalMaximumStoredRewards", function(v) HardcoreKitsConfig.SurvivalMaximumStoredRewards = v end },

    -- ---------- Bonus de Habilidade (skill boost) ----------
    { "InitialSkillGroupCountMin", function(v) HardcoreKitsConfig.InitialSkillGroupCountMin = v end },
    { "InitialSkillGroupCountMax", function(v) HardcoreKitsConfig.InitialSkillGroupCountMax = v end },

    -- ---------- Geral ----------
    { "MeleeHeavyWeightThreshold", function(v) HardcoreKitsConfig.MeleeHeavyWeightThreshold = v end },
    { "AutoOpenOnSpawnEnabled", function(v) HardcoreKitsConfig.AutoOpenOnSpawnEnabled = v end },
    { "SidebarButtonEnabled", function(v) HardcoreKitsConfig.SidebarButtonEnabled = v end },
}

-- DebugToolsEnabled never had its own HardcoreKits.* sandbox option (removed
-- 2026-08-21 to cut down the mod's total sandbox option count -- too many
-- options was tripping a Kahlua "200 locals" compiler limit in the game's own
-- SandboxVars codegen at boot). It reads LasciviousFactionsSystem.Debug
-- directly instead of declaring its own copy -- same feature flag, same
-- default (off). Not the security boundary: HardcoreKits_Debug.lua's
-- onClientCommand already requires HardcoreKitsIdentity.isAdmin(player) on
-- every debug command (true SP, the local host of a coop game -- explicitly
-- not remote guests -- or a real dedicated-server admin).
-- WindowDimOnDanger{Enabled,Radius,Alpha} used to be shared with
-- LasciviousShop the same way, but as of 2026-08-22 LasciviousShop removed
-- its copy too (explicit request, "sempre uso") -- there is no sandbox source
-- left for it on either side, so it's just a fixed default in
-- HardcoreKits_Config.lua now, same as LasciviousShop_Shared.lua.
local function applySharedOptions()
    local ff = SandboxVars and SandboxVars.LasciviousFactionsSystem
    if ff then
        HardcoreKitsConfig.DebugToolsEnabled = ff.Debug == true
    end
end

-- silent=true suprime os prints de resumo (usado pela reaplicacao periodica
-- abaixo, pra nao floodar o console numa sessao longa -- as falhas de
-- aplicacao continuam sempre visiveis, silent so afeta o log de rotina).
function HardcoreKitsSandboxBridge.apply(silent)
    pcall(applySharedOptions)
    local vars = sandboxVars()
    if not vars then
        if not silent then
            print("[HardcoreKits] SandboxVars.HardcoreKits indisponivel ainda -- usando os defaults de HardcoreKits_Config.lua")
        end
        return
    end
    local applied = 0
    for _, entry in ipairs(MAPPING) do
        local field, apply = entry[1], entry[2]
        local value = vars[field]
        if value ~= nil then
            local ok, err = pcall(apply, value)
            if ok then
                applied = applied + 1
            else
                print("[HardcoreKits] Falha aplicando a opcao de sandbox '" .. field .. "': " .. tostring(err))
            end
        end
    end
    if not silent then
        print(string.format("[HardcoreKits] Sandbox options aplicadas: %d/%d.", applied, #MAPPING))
    end
end

if HardcoreKitsSandboxBridge._serverStartedHandler and Events.OnServerStarted.Remove then
    Events.OnServerStarted.Remove(HardcoreKitsSandboxBridge._serverStartedHandler)
end
if HardcoreKitsSandboxBridge._gameStartHandler and Events.OnGameStart.Remove then
    Events.OnGameStart.Remove(HardcoreKitsSandboxBridge._gameStartHandler)
end
HardcoreKitsSandboxBridge._serverStartedHandler = HardcoreKitsSandboxBridge.apply
HardcoreKitsSandboxBridge._gameStartHandler = HardcoreKitsSandboxBridge.apply
Events.OnServerStarted.Add(HardcoreKitsSandboxBridge._serverStartedHandler)
Events.OnGameStart.Add(HardcoreKitsSandboxBridge._gameStartHandler) -- cobre singleplayer

-- ================= live-reload sem restart =================
-- pedido explicito do usuario: poder alterar as opcoes de sandbox NO MEIO DA
-- PARTIDA (pelo editor de sandbox do jogo) e o mod pegar o valor novo sem
-- precisar reiniciar. Antes disso, apply() so rodava UMA vez no boot
-- (OnServerStarted/OnGameStart) -- HardcoreKitsConfig ficava "congelado" com
-- o valor daquele instante pelo resto da sessao inteira. Reaplica a cada
-- SANDBOX_REAPPLY_INTERVAL_MS. Reaplicar um valor que nao mudou e inofensivo
-- (so reatribui o mesmo numero de novo) -- o intervalo abaixo (1 dia real) foi
-- escolhido a pedido explicito do usuario, que achou os 16s da primeira
-- versao desnecessariamente frequente/pesado para o que e, na pratica, um
-- ajuste raro (mexer no sandbox editor no meio da partida); quem quiser um
-- valor novo aplicado na hora ainda pode reabrir o mundo, o que ja dispara
-- OnServerStarted/OnGameStart normalmente.
local SANDBOX_REAPPLY_INTERVAL_MS = 24 * 60 * 60 * 1000 -- 1 dia real
local lastReapplyAtMs = 0
local function periodicReapply()
    local ok, now = pcall(getTimestampMs)
    if not ok or type(now) ~= "number" or now ~= now or now <= 0
        or now == math.huge or now == -math.huge then return end
    if now < lastReapplyAtMs then lastReapplyAtMs = 0 end
    if now - lastReapplyAtMs < SANDBOX_REAPPLY_INTERVAL_MS then return end
    lastReapplyAtMs = now
    HardcoreKitsSandboxBridge.apply(true)
end
if HardcoreKitsSandboxBridge._periodicHandler and Events.OnTick.Remove then
    Events.OnTick.Remove(HardcoreKitsSandboxBridge._periodicHandler)
end
HardcoreKitsSandboxBridge._periodicHandler = periodicReapply
Events.OnTick.Add(periodicReapply)
