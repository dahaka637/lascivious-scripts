-- Lascivious Scripts - Progressive Zombie Decay
-- Dedicated-server side: keeps vanilla ZombieLore aligned with world age.
-- Per-zombie movement is additionally enforced by the client simulation owner.

require "LasciviousScripts/ZombieDecay/Core"

local Core = LasciviousScripts.ZombieDecay
local ServerRuntime = {lastLoreRevision = nil, lastSummary = nil}
local PERSIST_KEY = "LasciviousScripts.ZombieDecay"
local PERSIST_VERSION = 1
local persistentReady = false

print("[LasciviousScripts/ZombieDecay] server module loaded v" .. Core.VERSION)

local function ensurePersistentOriginal(isNewGame)
    if persistentReady then return true end
    if not ModData or not ModData.getOrCreate then return false end
    local data = ModData.getOrCreate(PERSIST_KEY)
    if data.version == PERSIST_VERSION and Core.setOriginalLore(data.originalLore) then
        persistentReady = true
        return true
    end

    Core.captureOriginalLore()
    data.version = PERSIST_VERSION
    data.originalLore = Core.copyOriginalLore()
    data.capturedAtWorldDay = Core.getWorldAgeDays()
    persistentReady = true
    print("[LasciviousScripts/ZombieDecay] persistent original lore snapshot created")
    if isNewGame == false then
        print("[LasciviousScripts/ZombieDecay] WARNING: first persistent snapshot on an existing save; "
            .. "values already changed by an older version cannot be reconstructed automatically")
    end
    return true
end

local function updateWorldLore(isNewGame)
    if not ensurePersistentOriginal(isNewGame) then
        print("[LasciviousScripts/ZombieDecay] WARNING: persistent ModData unavailable; lore update skipped")
        return
    end
    local cfg = Core.getConfig()

    if not cfg.Enabled then
        Core.restoreOriginalLore()
        ServerRuntime.lastLoreRevision = nil
        ServerRuntime.lastSummary = nil
        return
    end

    local state = Core.buildState(Core.getWorldAgeDays(), cfg)
    Core.applyVanillaLore(state)

    local summary = Core.describeState(state)
    if state.loreRevision ~= ServerRuntime.lastLoreRevision then
        print("[LasciviousScripts/ZombieDecay] world phase changed: " .. summary)
        ServerRuntime.lastLoreRevision = state.loreRevision
    elseif cfg.DebugLogging and summary ~= ServerRuntime.lastSummary then
        print("[LasciviousScripts/ZombieDecay] " .. summary)
    end

    ServerRuntime.lastSummary = summary
end

Events.OnInitGlobalModData.Add(updateWorldLore)
Events.OnGameStart.Add(updateWorldLore)
Events.EveryTenMinutes.Add(updateWorldLore)
