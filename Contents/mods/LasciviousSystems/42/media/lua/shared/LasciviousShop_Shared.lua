LasciviousShop = LasciviousShop or {}

local LS = LasciviousShop

LS.MODULE = "LasciviousShop"
LS.DATA_KEY = "LasciviousShop_ServerData"

LS.CMD_REQUEST_STATE = "requestState"
LS.CMD_PURCHASE = "purchase"
LS.CMD_STATE = "state"
LS.CMD_PURCHASE_RESULT = "purchaseResult"
LS.CMD_ERROR = "error"

-- Player-to-player credit transfer. CMD_CREDITS_RECEIVED is unlike every
-- other command here: it targets the RECIPIENT, not whoever initiated the
-- request, and must work even if that recipient never has the shop window
-- open (see LS.onCreditsReceived in LasciviousShop_Client.lua, wired up
-- unconditionally, not from Window.lua).
LS.CMD_TRANSFER_LIST = "transferList"
LS.CMD_TRANSFER = "transferCredits"
LS.CMD_TRANSFER_RESULT = "transferResult"
LS.CMD_CREDITS_RECEIVED = "creditsReceived"

-- A vehicle placement search is deliberately conservative and therefore much
-- more expensive than delivering an inventory item. Bounding distinct vehicle
-- lines prevents a forged 40-line cart from monopolising the server thread.
-- Kept shared so the normal client never builds a cart the server will reject.
LS.MAX_VEHICLES_PER_PURCHASE = 4

-- Per-category price multipliers are a code-level knob only since 2026-08-21
-- (see LS.DEFAULTS.categoryPriceMultipliers below) -- they used to also be
-- individually sandbox-configurable via a "<Category>PriceMultiplier" option
-- per entry here, removed on explicit request. This id list is still used to
-- iterate the multiplier table itself (LS.copyCategoryPriceMultipliers,
-- LS.priceConfigurationHash).
LS.PRICE_CATEGORY_IDS = {
    "food", "drink", "firearm", "melee", "ammo", "resource",
    "medical", "clothing", "furniture", "other", "xp", "vehicle",
}

LS.DEFAULTS = {
    creditsPerZombieKill = 1.0,
    creditsPerHourSurvived = 1.0,
    -- 0 = no kill credit steal at all; 100 = the killer takes the victim's
    -- entire balance. Off by default: a server owner has to opt into this
    -- PvP economy mechanic deliberately.
    killCreditStealPercent = 0,
    -- How long a tracked player-vs-player hit still counts toward a kill.
    -- 900s (15min) comfortably covers a real firefight or someone bleeding
    -- out from the wound that actually killed them, while staying far short
    -- of "unrelated death hours/days later" (hunger, thirst...), which is
    -- the whole reason this isn't just character:getAttackedBy() at death.
    killCreditStealWindowSeconds = 900,
    -- Off by default: legacy behaviour wipes credits on death. When enabled,
    -- normal deaths keep the player's balance, but the PvP kill-steal cut is
    -- still deducted from the victim first.
    preserveCreditsOnDeath = false,
    priceMultiplier = 1.0,
    useCategoryPriceMultipliers = false,
    categoryPriceMultipliers = {
        food=1.0, drink=1.0, firearm=1.0, melee=1.0, ammo=1.0, resource=1.0,
        medical=1.0, clothing=1.0, furniture=1.0, other=1.0, xp=1.0, vehicle=1.0,
    },
    debugAddCredits = false,
    offersEnabled = true,
    offerRotationRealMinutes = 60,
    offerProductCountMin = 1,
    offerProductCountMax = 3,
    offerDiscountMinPercent = 5,
    offerDiscountMaxPercent = 80,
    offerBadgeEnabled = true,
    offerHighlightEnabled = true,
    offerHighlightRed = 247,
    offerHighlightGreen = 201,
    offerHighlightBlue = 72,
    windowDimOnDangerEnabled = true,
    windowDimOnDangerRadius = 4,
    windowDimOnDangerAlpha = 0.25,
    closeOnAttackEnabled = true,
}

local function finiteNumber(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

-- Public counterpart used by the client/server protocol boundaries. Kahlua's
-- tonumber/math.floor combination is not safe for NaN/infinity supplied by a
-- malformed command or damaged ModData, so callers must be able to reject
-- those values before doing integer arithmetic with them.
function LS.finiteNumber(value, fallback)
    return finiteNumber(value, fallback)
end

local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

function LS.getOptions()
    local raw = SandboxVars and SandboxVars.LasciviousShop or {}
    local d = LS.DEFAULTS
    local opts = {
        creditsPerZombieKill = clamp(finiteNumber(raw.CreditsPerZombieKill, d.creditsPerZombieKill), 0, 1000),
        creditsPerHourSurvived = clamp(finiteNumber(raw.CreditsPerHourSurvived, d.creditsPerHourSurvived), 0, 1000),
        killCreditStealPercent = clamp(finiteNumber(raw.KillCreditStealPercent, d.killCreditStealPercent), 0, 100),
        preserveCreditsOnDeath = raw.PreserveCreditsOnDeath == nil
            and d.preserveCreditsOnDeath or raw.PreserveCreditsOnDeath == true,
        -- 2026-08-21: no longer a sandbox option ("não tem necessidade... já
        -- acho equilibrado como está") -- fixed at the old default.
        killCreditStealWindowSeconds = d.killCreditStealWindowSeconds,
        priceMultiplier = clamp(finiteNumber(raw.PriceMultiplier, d.priceMultiplier), 0.05, 100),
        -- 2026-08-21: per-category multipliers and their on/off switch are no
        -- longer sandbox options -- explicit request ("vamos permitir em
        -- código esse ajuste facilitado, por variável... deixar só o
        -- geral"). Still fully functional: flip d.useCategoryPriceMultipliers
        -- to true and/or edit d.categoryPriceMultipliers above to use them,
        -- just as a code change instead of an in-game sandbox toggle.
        useCategoryPriceMultipliers = d.useCategoryPriceMultipliers,
        categoryPriceMultipliers = LS.copyCategoryPriceMultipliers(d.categoryPriceMultipliers),
        debugAddCredits = raw.DebugAddCredits == nil and d.debugAddCredits or raw.DebugAddCredits == true,
        offersEnabled = raw.OffersEnabled == nil and d.offersEnabled or raw.OffersEnabled == true,
        offerRotationRealMinutes = math.floor(clamp(finiteNumber(raw.OfferRotationRealMinutes,
            d.offerRotationRealMinutes), 1, 10080)),
        offerProductCountMin = math.floor(clamp(finiteNumber(raw.OfferProductCountMin,
            d.offerProductCountMin), 1, 50)),
        offerProductCountMax = math.floor(clamp(finiteNumber(raw.OfferProductCountMax,
            d.offerProductCountMax), 1, 50)),
        offerDiscountMinPercent = math.floor(clamp(finiteNumber(raw.OfferDiscountMinPercent,
            d.offerDiscountMinPercent), 1, 99)),
        offerDiscountMaxPercent = math.floor(clamp(finiteNumber(raw.OfferDiscountMaxPercent,
            d.offerDiscountMaxPercent), 1, 99)),
        -- 2026-08-21: no longer sandbox options -- explicit request ("isso é
        -- algo que eu nunca vou mudar, por default sempre ativo"). Always on,
        -- always the old default colour.
        offerBadgeEnabled = d.offerBadgeEnabled,
        offerHighlightEnabled = d.offerHighlightEnabled,
        offerHighlightRed = d.offerHighlightRed,
        offerHighlightGreen = d.offerHighlightGreen,
        offerHighlightBlue = d.offerHighlightBlue,
        -- 2026-08-21: the whole Interface page is no longer sandbox-exposed
        -- -- explicit request ("pois eu sempre uso"). Fixed at the old
        -- defaults (still client-read directly from LasciviousShop_Window.lua
        -- via these same LS.DEFAULTS, not round-tripped through server state).
        windowDimOnDangerEnabled = d.windowDimOnDangerEnabled,
        windowDimOnDangerRadius = d.windowDimOnDangerRadius,
        windowDimOnDangerAlpha = d.windowDimOnDangerAlpha,
        closeOnAttackEnabled = d.closeOnAttackEnabled,
    }
    if opts.offerProductCountMin > opts.offerProductCountMax then
        opts.offerProductCountMin, opts.offerProductCountMax = opts.offerProductCountMax, opts.offerProductCountMin
    end
    if opts.offerDiscountMinPercent > opts.offerDiscountMaxPercent then
        opts.offerDiscountMinPercent, opts.offerDiscountMaxPercent =
            opts.offerDiscountMaxPercent, opts.offerDiscountMinPercent
    end
    return opts
end

function LS.copyCategoryPriceMultipliers(source)
    local result = {}
    for _, categoryId in ipairs(LS.PRICE_CATEGORY_IDS) do
        result[categoryId] = clamp(finiteNumber(source and source[categoryId], 1), 0.05, 100)
    end
    return result
end

function LS.priceMultiplierForCategory(settings, categoryId)
    settings = settings or {}
    if settings.useCategoryPriceMultipliers then
        return clamp(finiteNumber(settings.categoryPriceMultipliers
            and settings.categoryPriceMultipliers[categoryId], 1), 0.05, 100)
    end
    return clamp(finiteNumber(settings.priceMultiplier, 1), 0.05, 100)
end

function LS.priceConfigurationHash(settings)
    settings = settings or {}
    local values = {
        tostring(settings.useCategoryPriceMultipliers == true),
        tostring(clamp(finiteNumber(settings.priceMultiplier, 1), 0.05, 100)),
    }
    for _, categoryId in ipairs(LS.PRICE_CATEGORY_IDS) do
        table.insert(values, categoryId)
        table.insert(values, tostring(clamp(finiteNumber(settings.categoryPriceMultipliers
            and settings.categoryPriceMultipliers[categoryId], 1), 0.05, 100)))
    end
    return table.concat(values, ":")
end

local function totalXPForLevel(perk, level)
    local ok, targetXP = pcall(function() return perk:getTotalXpForLevel(level) end)
    if not ok or tonumber(targetXP) == nil then
        ok, targetXP = pcall(function()
            local definition = PerkFactory and PerkFactory.getPerk and PerkFactory.getPerk(perk)
            return definition and definition:getTotalXpForLevel(level) or nil
        end)
    end
    return ok and finiteNumber(targetXP, nil) or nil
end

-- Returns the aggregate XP required to advance `quantity` consecutive levels.
-- XP is cumulative: two packages at level 4 cover the remainder to level 5
-- plus the complete level 5 -> 6 band.
function LS.xpRequiredForLevelsFromXP(perk, level, currentXP, quantity)
    level = math.max(0, math.min(10, math.floor(finiteNumber(level, 0))))
    if level >= 10 or not perk then return 0, level end
    local maximum = 10 - level
    quantity = math.max(1, math.min(maximum, math.floor(finiteNumber(quantity, 1))))
    local targetLevel = level + quantity
    local targetXP = totalXPForLevel(perk, targetLevel)
    currentXP = finiteNumber(currentXP, 0)
    if targetXP == nil then return 0, targetLevel end
    local remaining = targetXP - currentXP
    if remaining <= 0 then return 1, targetLevel end
    return math.max(1, math.ceil(remaining - 0.000001)), targetLevel
end

function LS.xpRequiredForLevels(player, perk, level, quantity)
    if not player or not perk then return 0, level end
    local ok, currentXP = pcall(function() return player:getXp():getXP(perk) end)
    if not ok then return 0, level end
    return LS.xpRequiredForLevelsFromXP(perk, level, currentXP, quantity)
end

function LS.xpRemainingToNextLevel(player, perk, level)
    return LS.xpRequiredForLevels(player, perk, level, 1)
end

-- Flat credit cost to fully complete each level-up (level N -> N+1),
-- independent of that perk's actual XP curve. Replaces pricing XP purchases
-- directly off the raw XP amount, which made high levels on steep perks
-- (tens of thousands of XP each) effectively unbuyable. Same table for every
-- perk, per explicit request -- no per-category surcharge.
LS.XP_LEVEL_UP_COST = {
    [0] = 75, [1] = 125, [2] = 175, [3] = 225, [4] = 275,
    [5] = 325, [6] = 375, [7] = 425, [8] = 475, [9] = 525,
}

-- Credit price (before category/global multiplier and offers) to advance
-- `quantity` consecutive levels from `level`, given `currentXP` already
-- banked toward the next one. Only the level currently in progress is
-- prorated by the fraction of it still missing; every further level bought
-- in the same purchase is charged at its full LS.XP_LEVEL_UP_COST, since it
-- necessarily starts at 0% once the current level's remainder is paid for.
function LS.xpLevelUpBasePriceFromXP(perk, level, currentXP, quantity)
    level = math.max(0, math.min(10, math.floor(finiteNumber(level, 0))))
    if level >= 10 or not perk then return 0 end
    local maximum = 10 - level
    quantity = math.max(1, math.min(maximum, math.floor(finiteNumber(quantity, 1))))
    currentXP = finiteNumber(currentXP, 0)

    local levelStartXP = totalXPForLevel(perk, level)
    local levelEndXP = totalXPForLevel(perk, level + 1)
    local currentLevelCost = LS.XP_LEVEL_UP_COST[level] or 0
    local price
    if levelStartXP ~= nil and levelEndXP ~= nil and levelEndXP > levelStartXP then
        local remainingPercent = clamp((levelEndXP - currentXP) / (levelEndXP - levelStartXP), 0, 1)
        price = currentLevelCost * remainingPercent
    else
        price = currentLevelCost
    end
    for i = 1, quantity - 1 do
        price = price + (LS.XP_LEVEL_UP_COST[level + i] or 0)
    end
    return price
end

function LS.xpLevelUpBasePrice(player, perk, level, quantity)
    if not player or not perk then return 0 end
    local ok, currentXP = pcall(function() return player:getXp():getXP(perk) end)
    if not ok then return 0 end
    return LS.xpLevelUpBasePriceFromXP(perk, level, currentXP, quantity)
end

-- Keeps cent rounding inside the exact-integer range of Lua doubles and also
-- gives corrupted/hostile persisted values a deterministic ceiling instead of
-- letting value*100 overflow back to infinity.
LS.MAX_CREDITS = 9000000000000

function LS.roundCredits(value)
    value = clamp(finiteNumber(value, 0), 0, LS.MAX_CREDITS)
    return math.floor(value * 100 + 0.5) / 100
end

function LS.formatCredits(value)
    value = LS.roundCredits(value)
    if math.abs(value - math.floor(value)) < 0.001 then
        return tostring(math.floor(value))
    end
    local s = string.format("%.2f", value)
    s = string.gsub(s, "0+$", "")
    s = string.gsub(s, "%.$", "")
    return s
end

-- Balance-style display: always two decimals, comma-separated (PT-BR convention),
-- e.g. "12,50" or "13,00". Unlike LS.formatCredits (used for prices/cart lines/
-- toasts, which are whole numbers by construction and read better bare), a total
-- balance routinely carries meaningful cents once faction tribute is involved.
function LS.formatCreditsFixed(value)
    value = LS.roundCredits(value)
    local s = string.format("%.2f", value)
    return (string.gsub(s, "%.", ","))
end

-- "kind=cure" products (currently only the emergency full cure) are not
-- priced from a flat catalog number: the worse off the character is, the
-- more the cure costs, between these two bounds.
LS.CURE_MIN_PRICE = 300
LS.CURE_MAX_PRICE = 1000

-- 0..1 "how badly hurt is this character" reading, shared verbatim between
-- client (live price preview while shopping) and server (authoritative price
-- at purchase time) so both land on the same number for the same player
-- state. Weighted: overall body health damage and zombie-virus progress
-- matter most (40% each), general distress (sickness/poison/pain/panic)
-- least (20%). A bitten-but-not-yet-registering-on-the-meters body part
-- forces the infection component to its worst value immediately -- the
-- moment of the bite is exactly when this item is meant to be most needed
-- and most expensive, not 30 seconds later once ZOMBIE_INFECTION has climbed.
function LS.cureSeverity(player)
    if not player then return 0 end
    local severity = 0
    pcall(function()
        local healthDeficit, infectionSeverity, distress = 0, 0, 0
        local body = player.getBodyDamage and player:getBodyDamage()
        if body then
            local health = tonumber(body.getOverallBodyHealth and body:getOverallBodyHealth()) or 100
            healthDeficit = clamp((100 - health) / 100, 0, 1)
            local parts = body.getBodyParts and body:getBodyParts()
            if parts then
                for i = 0, parts:size() - 1 do
                    local bp = parts:get(i)
                    if bp and bp:bitten() then infectionSeverity = 1 end
                end
            end
        end
        local stats = player.getStats and player:getStats()
        if stats then
            local infection = (tonumber(stats:get(CharacterStat.ZOMBIE_INFECTION)) or 0) / 100
            local fever = (tonumber(stats:get(CharacterStat.ZOMBIE_FEVER)) or 0) / 100
            infectionSeverity = math.max(infectionSeverity, clamp(infection, 0, 1), clamp(fever, 0, 1))
            local sickness = clamp(tonumber(stats:get(CharacterStat.SICKNESS)) or 0, 0, 1)
            local poison = clamp((tonumber(stats:get(CharacterStat.POISON)) or 0) / 100, 0, 1)
            local pain = clamp((tonumber(stats:get(CharacterStat.PAIN)) or 0) / 100, 0, 1)
            local panic = clamp((tonumber(stats:get(CharacterStat.PANIC)) or 0) / 100, 0, 1)
            distress = (sickness + poison + pain + panic) / 4
        end
        severity = clamp(0.40 * healthDeficit + 0.40 * infectionSeverity + 0.20 * distress, 0, 1)
    end)
    return severity
end

-- Combines two independent percent-off discounts (e.g. a per-product sale
-- offer and the faction Comércio upgrade's flat discount) by stacking them
-- SEQUENTIALLY -- the standard retail convention (apply A, then apply B to
-- the ALREADY-reduced amount), not additively, so two generous discounts can
-- never together imply more than 100% off. Used to fold both sources into
-- the single discountPercent LS.priceFor already accepts, rather than
-- changing that function's signature -- callers combine first, then call
-- LS.priceFor once with the combined number, so client preview and server
-- charge only ever round once and can never disagree with each other over
-- a second, independently-rounded pass.
function LS.combineDiscounts(a, b)
    a = clamp(finiteNumber(a, 0), 0, 100)
    b = clamp(finiteNumber(b, 0), 0, 100)
    return 100 - (100 - a) * (100 - b) / 100
end

function LS.priceFor(product, discountPercent, multiplier, xpBasePrice, severity)
    if not product then return 0, 0 end
    multiplier = clamp(finiteNumber(multiplier, 1), 0.05, 100)
    local basePrice = tonumber(product.price) or 0
    if product.kind == "xp" then
        basePrice = math.max(0, finiteNumber(xpBasePrice, 0))
    elseif product.kind == "cure" then
        local s = clamp(finiteNumber(severity, 0), 0, 1)
        basePrice = LS.CURE_MIN_PRICE + s * (LS.CURE_MAX_PRICE - LS.CURE_MIN_PRICE)
    end
    local original = math.max(1, math.floor(basePrice * multiplier + 0.5))
    local discount = math.floor(clamp(finiteNumber(discountPercent, 0), 0, 99))
    if discount <= 0 then return original, original end
    local current = math.max(1, math.floor(original * (100 - discount) / 100 + 0.5))
    -- A real offer must visibly lower the price even when a small percentage on
    -- a cheap product would round back to the original integer value.
    if original > 1 then current = math.min(current, original - 1) end
    return current, original
end

function LS.text(key, fallback, ...)
    local fullKey = "UI_LasciviousShop_" .. tostring(key)
    if getText then
        local ok, value = pcall(getText, fullKey, ...)
        if ok and type(value) == "string" and value ~= "" and value ~= fullKey then return value end
    end
    local value = fallback or tostring(key)
    local args = { ... }
    -- Replace every numbered placeholder in one pass. Function replacements
    -- return user text verbatim (so '%' in a player/product name is harmless),
    -- and one pass prevents an inserted name such as "%2" from being mistaken
    -- for the next placeholder on a later substitution iteration.
    value = string.gsub(value, "%%(%d+)", function(index)
        local position = tonumber(index)
        if position and position >= 1 and position <= #args then return tostring(args[position]) end
        return "%" .. tostring(index)
    end)
    return value
end

function LS.log(message)
    print("[LasciviousShop] " .. tostring(message))
end
