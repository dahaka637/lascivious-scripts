require "LasciviousShop_Shared"

local LS = LasciviousShop

-- "ammo" renamed from "Munição" to "Munição e Acessórios" -- explicit
-- request, folding every DescWeaponPart entry (scopes, gun lights, lasers,
-- suppressors etc., vanilla and modded) into this tab instead of "other" so
-- ammo and the gear that goes ON a firearm live together.
LS.CATEGORIES = {
    { id="offers",   labelKey="CategoryOffers",   fallback="OFERTAS",                    icon="tag-solid" },
    { id="all",      labelKey="CategoryAll",      fallback="Todos os itens",            icon="border-all-solid" },
    { id="food",     labelKey="CategoryFood",     fallback="Comida",                    icon="burger-solid" },
    { id="drink",    labelKey="CategoryDrink",    fallback="Bebidas",                   icon="wine-bottle-solid" },
    { id="firearm",  labelKey="CategoryFirearm",  fallback="Armas de fogo",             icon="gun-solid" },
    { id="melee",    labelKey="CategoryMelee",    fallback="Armas corpo a corpo",       icon="hand-fist-solid" },
    { id="ammo",     labelKey="CategoryAmmo",     fallback="Munição e Acessórios",      icon="box-solid" },
    { id="resource", labelKey="CategoryResource", fallback="Recursos",                  icon="hammer-solid" },
    { id="medical",  labelKey="CategoryMedical",  fallback="Medicina",                  icon="kit-medical-solid" },
    { id="clothing", labelKey="CategoryClothing", fallback="Vestuário",                icon="shirt-solid" },
    { id="furniture",labelKey="CategoryFurniture",fallback="Móveis",                    icon="couch-solid" },
    { id="vehicle",  labelKey="CategoryVehicle",  fallback="Veículos",                  icon="car-solid" },
    { id="other",    labelKey="CategoryOther",    fallback="Outros",                    icon="cubes-solid" },
    { id="xp",       labelKey="CategoryXP",       fallback="XP de habilidades",         icon="arrow-up-right-dots-solid" },
}

-- The catalog intentionally contains only complete, useful Build 42 items.
-- Broken pieces, debug objects and purely decorative variants are omitted.
-- Every purchase always delivers exactly one instance of the selected item.
LS.PRODUCTS = {}

local function stableId(category, fullType)
    local id = string.lower(tostring(fullType or "item"))
    id = string.gsub(id, "^base%.", "")
    id = string.gsub(id, "[^a-z0-9]+", "_")
    id = string.gsub(id, "^_+", "")
    id = string.gsub(id, "_+$", "")
    return category .. "_" .. id
end

-- modInfo (optional, nil for every plain Base.* call below) tags every
-- product from this call with its source mod and, if given, registers a
-- cheap presence probe -- see LS.addModdedItems below, the public entry
-- point that actually passes modInfo. Kept as a bolt-on 5th argument
-- instead of a new code path so this stays the exact same function every
-- addItems(...) call in this file already goes through.
local function addItems(category, descKey, descFallback, entries, modInfo)
    local sourceMod = modInfo and modInfo.id or nil
    if modInfo and modInfo.isPresent then
        LS.MOD_PRESENCE_CHECKS = LS.MOD_PRESENCE_CHECKS or {}
        LS.MOD_PRESENCE_CHECKS[modInfo.id] = modInfo.isPresent
    end
    for _, entry in ipairs(entries) do
        local fullType = tostring(entry[1])
        if not string.find(fullType, ".", 1, true) then fullType = "Base." .. fullType end
        table.insert(LS.PRODUCTS, {
            id=entry[3] or stableId(category, fullType), category=category, kind="item",
            fullType=fullType, quantity=1, price=entry[2],
            fallback=entry[4] or string.gsub(fullType, "^Base%.", ""),
            descKey=entry[5] or descKey, descFallback=entry[6] or descFallback,
            extraCategories=entry.extraCategories,
            sourceMod=sourceMod,
            -- Wins over the item's own real getDisplayName() in LS.productName below
            -- (entry.fallback/nameKey only ever apply when that native lookup fails
            -- outright). Exists for the rare case a mod's own translation is missing
            -- for a given locale, or present but wrong/misleading -- see the PSR.*
            -- entries further down for a real example of both.
            --
            -- nameOverrideKey (routed through LS.text/getText, resolving from this
            -- mod's OWN UI.json) takes priority over the raw nameOverride string.
            -- Any accented text hardcoded directly as a Lua literal here renders as
            -- "?" in-game for letters like ã/ç -- confirmed NOT a font/glyph gap
            -- (every UIFont's .fnt lists those codepoints) and NOT a file-encoding
            -- problem (this file is valid UTF-8 throughout) -- getText()'s JSON
            -- loader decodes UTF-8 correctly where the raw-literal draw path does
            -- not. nameOverride alone stays as the last-resort fallback LS.text
            -- itself falls back to if the key is ever missing.
            nameOverride=entry.nameOverride,
            nameOverrideKey=entry.nameOverrideKey,
        })
    end
end

-- ===================================================================
-- Modded content: the public, ergonomic entry point for adding items from
-- OTHER installed mods (clothing, weapons, anything with a normal
-- fullType) to the shop. Safe by construction, not by cleverness --
-- LasciviousShop_Server.lua's validateCatalog() already runs every single
-- product (vanilla or modded) through a real getScriptManager():FindItem()
-- check at boot and silently disables whatever doesn't resolve, so a mod
-- that gets updated (an item renamed/removed) or removed from the server
-- entirely just makes its items quietly unavailable -- never a crash,
-- never a broken purchase. That protection is unconditional and applies
-- here with zero extra work; everything below is purely about making
-- ADDING modded entries easy and making the resulting warnings, if any,
-- actually explain themselves instead of reading as a bare product id.
--
-- Usage -- identical entry syntax to every addItems(...) call above
-- ({"FullType.Here", price}, optional id/display-name/description
-- overrides, extraCategories={...}), the only difference is modInfo up
-- front:
--
--   LS.addModdedItems({
--       id = "SomeWeaponsMod",                       -- shows up in log warnings
--       isPresent = function() return SomeModGlobal ~= nil end,  -- optional
--   }, "melee", "DescMelee", "Arma corpo a corpo", {
--       {"SomeWeaponsMod.CoolSword", 240},           -- shows the mod's own display name
--       {"SomeWeaponsMod.CoolAxe", 190, nil, "Machado Legal"},  -- 4th field overrides it if ever needed
--   })
--
-- modInfo.id is required. modInfo.isPresent is optional and purely
-- diagnostic (see validateCatalog()'s comment in LasciviousShop_Server.lua
-- for exactly why it can never affect whether an item is actually sold) --
-- if provided, probe something the mod ITSELF sets up (a global table/
-- namespace its own files create), never a Steam Workshop id: those aren't
-- stable across install methods (local install, different workshop
-- mirror...), so a workshop-id scan can silently miss a mod that's
-- genuinely there. No working isPresent for a given mod? Just omit it --
-- the item is still fully protected by the unconditional FindItem check.
--
-- Display names take care of themselves: LS.productName reads the item's
-- REAL in-game display name straight off its script (getDisplayName()),
-- vanilla or modded, so a modded sword shows up exactly as that mod named
-- it without any extra work here. The 4th entry field (explicit name) only
-- exists as a manual override for the rare case a mod's own name doesn't
-- fit the shop card -- it's never required. The auto-generated fallback
-- (built from the raw fullType, namespace prefix and all) only matters if
-- that lookup fails outright -- which only happens for an item that's
-- already invalid and therefore never shown to players at all (see
-- LasciviousShop_SearchIndex.lua, every result list filters out
-- invalidProducts before anything reaches the UI).
--
-- The item IS valid but the mod's own name for it is missing (no translation
-- for a locale this server actually uses) or present but wrong/misleading?
-- The 4th field can't help -- it never even runs, since the native lookup
-- already succeeded. Set entry.nameOverride instead: it wins over
-- getDisplayName() unconditionally, e.g.
-- {"SomeMod.Thing", 240, nil, nil, nil, nil, nameOverride="Nome Correto"}.
function LS.addModdedItems(modInfo, category, descKey, descFallback, entries)
    if type(modInfo) ~= "table" or type(modInfo.id) ~= "string" or modInfo.id == "" then
        error("LS.addModdedItems: modInfo.id is required", 2)
    end
    addItems(category, descKey, descFallback, entries, modInfo)
end

-- Food: dependable preserved food, pantry staples, useful snacks, fresh
-- produce, proteins, and (2026-08-21 expansion) proper ready-to-eat prepared
-- meals/bakery/desserts -- explicit gap flagged by the user ("falta MUITA
-- coisa, como alimentos perecíveis como um x-salada, tortas etc"). The old
-- "Recipe states, opened cans and cooked variants remain excluded" rule is
-- relaxed specifically for finished, sealed-for-sale prepared dishes like
-- these (a burger/pie/pizza IS the product a real shop sells, not a
-- half-made recipe state) -- raw dough/uncooked/"*Recipe"/"*_single"
-- (opened-pack) states are still excluded. Every new id below was verified
-- against the real Build 42 item scripts (DisplayCategory=Food, has a real
-- DaysFresh/DaysTotallyRotten spoilage window) before being added, same
-- standard as everything already here. Drinks (water, juice, soda, beer,
-- wine, spirits, coffee/tea) moved OUT to their own "drink" category below
-- -- explicit ask, "separar a comida da bebida".
addItems("food", "DescFood", "Alimento", {
    {"CannedBolognese",24}, {"CannedCarrots2",18}, {"CannedChili",26},
    {"CannedCornedBeef",28}, {"CannedCorn",19},
    {"CannedFruitCocktail",23}, {"CannedMushroomSoup",21}, {"CannedPeaches",22},
    {"CannedPeas",18}, {"CannedPineapple",22}, {"CannedPotato2",20},
    {"CannedSardines",24}, {"CannedTomato2",18}, {"TinnedBeans",22,"beans"},
    {"TinnedSoup",21}, {"TunaTin",26},

    {"Cereal",28},
    {"DriedBlackBeans",32}, {"DriedChickpeas",32}, {"DriedKidneyBeans",32},
    {"DriedLentils",30}, {"DriedSplitPeas",30}, {"DriedWhiteBeans",32},
    {"Macaroni",30}, {"Pasta",32}, {"Rice",34}, {"Flour2",30},
    {"Cornflour2",28}, {"Cornmeal2",28}, {"Sugar",28}, {"SugarBrown",30},
    {"Salt",16}, {"Pepper",18}, {"Honey",34}, {"PeanutButter",32},
    {"OilOlive",42}, {"OilVegetable",34}, {"MapleSyrup",35},
    {"JamFruit",30}, {"JamMarmalade",30}, {"TomatoPaste",18}, {"Marinara",25},
    {"Ketchup",18}, {"Mustard",17}, {"Hotsauce",19}, {"Soysauce",19},
    {"Butter",28}, {"Margarine",24}, {"Lard",24},

    {"Chocolate",16,"chocolate"}, {"Chocolate_Butterchunkers",16},
    {"Chocolate_Crackle",16}, {"Chocolate_Deux",16}, {"Chocolate_GalacticDairy",16},
    {"Chocolate_RoysPBPucks",16}, {"Chocolate_Smirkers",16}, {"Chocolate_SnikSnak",16},
    {"Crisps",14}, {"Crisps2",14}, {"Crisps3",14}, {"Crisps4",14},
    {"TortillaChips",15}, {"BeefJerky",22}, {"DehydratedMeatStick",20},
    {"Peanuts",16}, {"SunflowerSeeds",14}, {"Crackers",14}, {"GranolaBar",15},
    {"Popcorn",13}, {"Pretzel",14}, {"ScoutCookies",18}, {"Marshmallows",15},
    {"GrahamCrackers",15}, {"CandyCaramels",14}, {"GummyBears",14},

    {"Apple",12}, {"Banana",11}, {"Grapefruit",13}, {"Grapes",14}, {"Mango",15},
    {"Orange",12}, {"Peach",13}, {"Pear",12}, {"Pineapple",22}, {"Watermelon",28},
    {"Strewberrie",15}, {"Avocado",16}, {"BellPepper",12}, {"Broccoli",13},
    {"BrusselSprouts",13}, {"Cabbage",15}, {"Carrots",11}, {"Cauliflower",14},
    {"Corn",13}, {"Cucumber",11}, {"Eggplant",13}, {"Kale",12}, {"Leek",12},
    {"Lettuce",12}, {"Onion",11}, {"Potato",12}, {"Pumpkin",25}, {"Spinach",12},
    {"SweetPotato",13}, {"Tomato",11}, {"Turnip",11}, {"Zucchini",12},

    {"Beef",34}, {"Steak",38}, {"MincedMeat",30}, {"Pork",34}, {"PorkChop",32},
    {"MuttonChop",34}, {"Chicken",32}, {"ChickenWhole",48}, {"ChickenWings",25},
    {"TurkeyLegs",30}, {"TurkeyWings",28}, {"Venison",38}, {"Rabbitmeat",32}, {"Salmon",36},
    {"Shrimp",30}, {"Squid",30}, {"Lobster",45}, {"Egg",10}, {"EggCarton",36},
    {"Cheese",30}, {"Salami",28}, {"Pepperoni",27}, {"Sausage",25}, {"Baloney",22},

    -- Ready-to-eat prepared meals -- the "x-salada"/"torta" gap.
    {"Burger",32}, {"Burrito",28}, {"Taco",22}, {"Pizza",26}, {"PizzaWhole",65},
    {"Sandwich",20}, {"BaguetteSandwich",26}, {"Hotdog",20}, {"TacoShell",14},
    {"BunsHamburger",18}, {"BunsHotdog",16},

    -- Bakery and desserts.
    {"Pie",32}, {"PieApple",36}, {"PieBlueberry",36}, {"PieKeyLime",38},
    {"PieLemonMeringue",38}, {"PiePumpkin",36},
    {"CakeCheeseCake",34}, {"CakeStrawberryShortcake",34}, {"Cupcake",14},
    {"MuffinFruit",15}, {"MuffinGeneric",13},
    {"CookieChocolateChip",12}, {"CookieJelly",12}, {"CookiesChocolate",12},
    {"CookiesOatmeal",12}, {"CookiesShortbread",12}, {"CookiesSugar",12},
    {"DoughnutChocolate",14}, {"DoughnutFrosted",14}, {"DoughnutJelly",14},
    {"DoughnutPlain",12}, {"BagelPlain",16}, {"BagelPoppy",17}, {"BagelSesame",17},
    {"Toast",12},

    -- Comfort food, breakfast and frozen treats.
    {"Salad",22}, {"FruitSalad",20}, {"NoodleSoup",20}, {"StewBowl",24},
    {"PotOfStew",55}, {"Oatmeal",16}, {"EggOmelette",22}, {"Waffles",20},
    {"ChickenNuggets",24}, {"FrenchFries",16}, {"Fries",20},
    {"Icecream",18}, {"ConeIcecream",16}, {"IcecreamSandwich",15}, {"Popsicle",10},
})

-- Final pantry pass: useful Build 42 groceries that were not represented by
-- the original staples. Recipe states, opened cans and cooked variants remain
-- excluded; everything below is a native sealed, raw or ready-to-eat product.
addItems("food", "DescFood", "Alimento", {
    {"Yeast",20}, {"GravyMix",18}, {"PancakeMix",26},
    {"Vinegar2",22}, {"BalsamicVinegar",28}, {"RiceVinegar",24},
    {"MayonnaiseFull",24}, {"RemouladeFull",24}, {"BBQSauce",20},
    {"SesameOil",32}, {"OatsRaw",27}, {"Macandcheese",28},
    {"Ramen",18}, {"BouillonCube",12}, {"PowderedGarlic",17},
    {"PowderedOnion",17}, {"SeasoningSalt",16}, {"Cinnamon",18},
    {"Seasoning_Basil",16}, {"Seasoning_Chives",16},
    {"Seasoning_Cilantro",16}, {"Seasoning_Oregano",16},
    {"Seasoning_Parsley",16}, {"Seasoning_Rosemary",16},
    {"Seasoning_Sage",16}, {"Seasoning_Thyme",16},

    {"CannedBellPepper",20}, {"CannedBroccoli",20},
    {"CannedCabbage",21}, {"CannedEggplant",20}, {"CannedLeek",20},
    {"CannedRedRadish",19}, {"CannedMilk",24}, {"CannedRoe",30},
    {"Bread",24}, {"Baguette",25}, {"Biscuit",14},
    {"Cornbread",20}, {"Croissant",18}, {"Processedcheese",27},
    {"SourCream",24}, {"Yoghurt",18}, {"TVDinner",30},
    {"Frozen_ChickenNuggets",28}, {"Frozen_FishFingers",28},
    {"Frozen_FrenchFries",22}, {"Frozen_TatoDots",22},
    {"Bacon",34}, {"Ham",38}, {"HotdogPack",32},

    {"Cherry",13}, {"DriedApricots",19}, {"Lemon",11}, {"Lime",11},
    {"Capers",17}, {"Olives",18}, {"Pickles",18}, {"Tofu",24},
    {"Blackbeans",15}, {"CornFrozen",16}, {"Daikon",12}, {"Edamame",17},
    {"Garlic",13}, {"GreenOnions",12}, {"Greenpeas",14},
    {"MixedVegetables",18}, {"Peas",14}, {"PepperHabanero",13},
    {"PepperJalapeno",12}, {"Soybeans",16}, {"Squash",14},
    {"SugarBeet",13}, {"RedRadish",11},
})

-- Drink: split out of "food" 2026-08-21, explicit ask ("separar a comida da
-- bebida") -- every bottled/canned/boxed beverage, brewing/mixing ingredient
-- (coffee, tea, cocoa powder, cocktail mixers) and spirit. Same "sealed,
-- native Build 42 product" standard as food.
addItems("drink", "DescDrink", "Bebida", {
    {"WaterBottle",15,"water"}, {"WaterRationCan",18}, {"Milk",18},
    {"Milk_Personalsized",12}, {"MilkChocolate_Personalsized",14}, {"MilkBottle",22},
    {"JuiceBox",12}, {"JuiceBoxApple",12}, {"JuiceBoxFruitpunch",12}, {"JuiceBoxOrange",12},
    {"JuiceCranberry",22}, {"JuiceFruitpunch",22}, {"JuiceGrape",22},
    {"JuiceLemon",22}, {"JuiceOrange",22}, {"JuiceTomato",22}, {"CannedFruitBeverage",20},
    {"Pop",12}, {"Pop2",12}, {"Pop3",12}, {"PopBottle",18}, {"SodaCan",12},
    {"Coffee2",38}, {"Teabag2",24}, {"CocoaPowder",25},

    {"BeerBottle",18}, {"BeerCan",15}, {"BeerImported",22},
    {"BeerPack",96}, {"BeerCanPack",78}, {"Cider",22},
    {"Wine",34}, {"Wine2",38}, {"WineAged",58}, {"WineScrewtop",34},
    {"WineWhite_Boxed",76}, {"WineRed_Boxed",76}, {"WineBox",72},
    {"Champagne",48}, {"Port",38}, {"Sherry",38}, {"Vermouth",40},
    {"Whiskey",45}, {"Scotch",48}, {"Vodka",42}, {"Rum",42}, {"Gin",42},
    {"Tequila",42}, {"Brandy",44}, {"CoffeeLiquer",40}, {"Curacao",40},
    {"Grenadine",28}, {"Bitters",28}, {"SimpleSyrup",22},
})

-- Every standard firearm currently defined by the Build 42 Base module. Toy
-- cap guns are deliberately not saleable combat equipment.
addItems("firearm", "DescFirearm", "Arma de fogo", {
    {"Pistol",110}, {"Pistol2",125}, {"Pistol3",155},
    {"Revolver_Short",90}, {"Revolver",135,"revolver"}, {"Revolver_Long",175},
    {"DoubleBarrelShotgun",190}, {"DoubleBarrelShotgunSawnoff",165},
    {"Shotgun",210,"shotgun"}, {"ShotgunSawnoff",180}, {"JS3T_Shotgun",260},
    {"VarmintRifle",220}, {"HuntingRifle",260}, {"JS14_Rifle",240},
    {"L92_Carbine",225}, {"L94_Rifle",250}, {"MSR7T_Rifle",300},
    {"TrapperCarbine",210}, {"AssaultRifle2",320}, {"AssaultRifle",340},
})

-- All Base ammunition formats used by the firearms above: loose rounds,
-- boxes, bulk cartons and empty magazines.
addItems("ammo", "DescAmmoRound", "Munição avulsa", {
    {"Bullets9mm",3}, {"Bullets45",4}, {"Bullets38",3}, {"Bullets357",4},
    {"Bullets44",5}, {"556Bullets",5}, {"308Bullets",6}, {"3030Bullets",5},
    {"ShotgunShells",6},
})
addItems("ammo", "DescAmmoBox", "Caixa de munição", {
    {"Bullets9mmBox",52,"ammo9"}, {"Bullets45Box",54,"ammo45"},
    {"Bullets38Box",48}, {"Bullets357Box",58}, {"Bullets44Box",58},
    {"556Box",62}, {"308Box",64}, {"3030Box",60}, {"ShotgunShellsBox",58,"ammo12"},
})
addItems("ammo", "DescAmmoCarton", "Pacote de caixas", {
    {"Bullets9mmCarton",624}, {"Bullets45Carton",648}, {"Bullets38Carton",576},
    {"Bullets357Carton",696}, {"Bullets44Carton",696}, {"556Carton",744},
    {"308Carton",768}, {"3030Carton",720}, {"ShotgunShellsCarton",696},
})
addItems("ammo", "DescMagazine", "Carregador vazio", {
    {"9mmClip",24}, {"45Clip",24}, {"44Clip",26}, {"556Clip",34},
    {"M14Clip",34}, {"JS14_Clip",32},
})

-- Useful intact blades, blunt weapons, axes, spears and strong crafted combat
-- variants. Cutlery, pens, broken handles and joke weapons are excluded.
-- Every "Forged" (and "_Old"/numbered) counterpart intentionally excluded
-- below, not missed -- confirmed by decompiling the real vanilla item
-- scripts one field at a time (MinDamage/MaxDamage/MaxHitcount/MaxRange/
-- ConditionMax/Weight/CriticalChance/etc, all identical) that each one is
-- mechanically THE EXACT SAME weapon as its plain counterpart, just a
-- different item id PZ uses to track "found" vs "player-forged" provenance
-- -- they even share the same in-game DISPLAY NAME (Base.Machete and
-- Base.MacheteForged both show as just "Machete", etc). Selling both was a
-- real bug ("há duas machetes... são exatamente a mesma machete"), not a
-- deliberate crude/forged quality tier the way CrudeKnife/HuntingKnife
-- actually are (those DO have different stats and stay separate entries).
-- Removed: HuntingKnifeForged, KitchenKnifeForged, MeatCleaverForged,
-- MacheteForged, BallPeenHammerForged, ClubHammerForged, HammerForged,
-- CrowbarForged, PanForged, GardenFork_Forged, GardenHoeForged,
-- HandScytheForged, HandAxeForged, PickAxeForged, WoodAxeForged, SpadeForged,
-- RailroadSpikePullerOld, Sledgehammer2, SledgehammerForged.
addItems("melee", "DescMelee", "Arma corpo a corpo", {
    {"HuntingKnife",90}, {"FightingKnife",95},
    {"HandguardDagger",98}, {"LongCrudeKnife",62}, {"CrudeKnife",42},
    {"RailroadSpikeKnife",52}, {"KnifeButterfly",46}, {"SwitchKnife",46},
    {"KitchenKnife",38, extraCategories={"other"}},
    {"KnifeSushi",42, extraCategories={"other"}},
    {"SteakKnife",34, extraCategories={"other"}}, {"IcePick",52, extraCategories={"other"}},
    {"MeatCleaver",48, extraCategories={"other"}},
    {"BreadKnife",26, extraCategories={"other"}},
    {"KnifeFillet",30, extraCategories={"other"}},
    {"KnifeParing",24, extraCategories={"other"}},
    {"FlintKnife",26}, {"StoneKnifeLong",44}, {"KnifePocket",42}, {"SmallKnife",42},
    {"LargeKnife",78}, {"LargeKnife_Scrap",60}, {"MacheteKnife",78},

    {"ShortSword",210}, {"CrudeShortSword",155}, {"Sword",320}, {"CrudeSword",220},
    {"Sword_Scrap",230}, {"Machete",230},
    {"Machete_Crude",130}, {"Katana",560},

    {"Hammer",68}, {"BallPeenHammer",64}, {"ClubHammer",66}, {"PipeWrench",78},
    {"Wrench",58}, {"TireIron",68}, {"LeadPipe",88}, {"MetalBar",70}, {"MetalPipe",66},
    {"Nightstick",105}, {"ShortBat",66}, {"SpikedShortBat",88},
    {"BaseballBat",85}, {"BaseballBat_Metal",100}, {"BaseballBat_Nails",110},
    {"BaseballBat_Spiked",130}, {"BaseballBat_Metal_Bolts",135},
    {"Crowbar",145}, {"LongMace",260}, {"LongMace_Stone",150}, {"LongSpikedClub",75},
    {"Mace",165}, {"Mace_Stone",100}, {"Morningstar_Scrap",140},
    {"Morningstar_Scrap_Short",100}, {"BlockMace",95}, {"BlockMaul",175},
    {"ScrapMaul",150}, {"StoneMaul",110}, {"EngineMaul",175},
    {"Sledgehammer",390},
    {"RailroadSpikePuller",260},

    {"BoneClub",48}, {"BoneClub_Spiked",78}, {"LargeBoneClub",62},
    {"LargeBoneClub_Spiked",90}, {"Pan",38, extraCategories={"other"}},
    {"GridlePan",36, extraCategories={"other"}},
    {"RollingPin",24, extraCategories={"other"}}, {"Saucepan",42, extraCategories={"other"}},
    {"SaucepanCopper",48, extraCategories={"other"}},
    {"BarBell",95}, {"BaseballBat_Crafted",78}, {"BowlingPin",34},
    {"CanoePadel",75}, {"CanoePadelX2",110}, {"DumbBell",46},
    {"FieldHockeyStick",48}, {"Golfclub",65}, {"IceHockeyStick",48},
    {"LaCrosseStick",48}, {"Poolcue",32}, {"TennisRacket",32},

    {"HandAxe",135}, {"Axe",200,"axe"}, {"Axe_Old",180}, {"WoodAxe",150},
    {"PickAxe",245}, {"AxeStone",80}, {"StoneAxeLarge",120},
    {"Axe_Sawblade",115}, {"Axe_Sawblade_Hatchet",85}, {"Axe_ScrapCleaver",110},
    {"HandScythe",80}, {"EntrenchingTool",90},
    {"GardenFork",165}, {"GardenHoe",100},
    {"PrimitiveScythe",55}, {"Shovel",150}, {"Shovel2",150},
    {"SpadeWood",55}, {"SnowShovel",140}, {"Stake",28},

    {"File",55}, {"FireplacePoker",78}, {"HammerStone",32},
    {"HandAxe_Old",120}, {"IceAxe",120}, {"LargeHook",55},
    {"CarpentryChisel",55}, {"MasonsChisel",55}, {"MasonsTrowel",34},
    {"MetalworkingChisel",58}, {"MetalworkingPunch",58}, {"Multitool",65},
    {"Ratchet",56}, {"Saw_Flint",40},
    {"Screwdriver_Improvised",30}, {"Screwdriver_Old",34}, {"SmithingHammer",78},
    {"WoodenMallet",42},

    {"SpearCrafted",50}, {"SpearCraftedFireHardened",85}, {"SpearCrude",65},
    {"SpearCrudeLong",85}, {"SpearShort",145}, {"SpearLong",165},
    {"SpearStone",60}, {"SpearStoneLong",78}, {"Spear_Bone",52}, {"Spear_BoneLong",62},
    {"SpearGlass",56}, {"SpearKnife",88}, {"SpearKnifeSmall",80},
    {"SpearHuntingKnife",140}, {"SpearFightingKnife",150}, {"SpearLargeKnife",130},
    {"SpearScrapKnife",115}, {"SpearHandFork",95}, {"SpearScissors",78},
    {"SpearScrewdriver",85}, {"SpearSteakKnife",78},

    {"Cudgel_Bone",130}, {"Cudgel_Brake",165}, {"Cudgel_GardenForkHead",165},
    {"Cudgel_Nails",140}, {"Cudgel_Railspike",165}, {"Cudgel_Sawblade",165},
    {"Cudgel_ScrapSheet",135}, {"Cudgel_SpadeHead",165}, {"Cudgel_Spike",165},
    {"ScrapWeaponGardenFork",150}, {"ScrapWeaponRakeHead",120},
    {"ScrapWeaponSpade",150}, {"ScrapWeapon_Brake",140},
    {"BaseballBat_Can",90}, {"BaseballBat_GardenForkHead",140},
    {"BaseballBat_Metal_Sawblade",150}, {"BaseballBat_RailSpike",145},
    {"BaseballBat_RakeHead",145}, {"BaseballBat_Sawblade",145},
    {"BaseballBat_ScrapSheet",115}, {"BucketMace_Metal",170}, {"BucketMace_Wood",160},
    {"KettleMace_Metal",170}, {"KettleMace_Wood",160},
    {"JawboneBovide_Morningstar",210}, {"Hatchet_Bone",65},
    {"LongHandle_Brake",100}, {"LongHandle_Railspike",90},
    {"LongHandle_RakeHead",90}, {"LongHandle_Sawblade",90},
    {"MeatCleaver_Scrap",38}, {"MetalPipe_Railspike",78},
    {"Plank_Brake",105}, {"Plank_Nails",65}, {"Plank_Sawblade",95},
    {"ShortBat_Nails",88}, {"ShortBat_RailSpike",92},
    {"ShortBat_RakeHead",95}, {"ShortBat_Sawblade",92},
    {"TableLeg_Chain",95}, {"TableLeg_Nails",65}, {"TableLeg_Sawblade",100},
})

-- Construction, mechanics, metalworking, tailoring, electronics, camping,
-- farming and fishing supplies. Prices intentionally keep generators, anvils,
-- fuel and high-grade metal as meaningful long-term purchases.
addItems("resource", "DescResource", "Recurso ou ferramenta", {
    {"Plank",22,"planks"}, {"LargePlank",34}, {"Log",42}, {"NailsBox",28,"nails"},
    {"ScrewsBox",30}, {"DuctTape",30,"ducttape"}, {"Woodglue",28}, {"Glue",20},
    {"Epoxy",32}, {"FiberglassTape",32}, {"Twine",18}, {"Rope",24},
    {"Thread",16}, {"Thread_Aramid",32}, {"Wire",24}, {"BarbedWire",32},
    {"ElectricWire",26}, {"WeldingRods",38}, {"Zipties",18},

    {"IronBar",64}, {"SteelBar",78},
    {"SheetMetal",58}, {"SmallSheetMetal",34}, {"IronIngot",90}, {"SteelIngot",115},
    {"CopperIngot",88}, {"IronOre",55}, {"CopperOre",52},
    {"IronScrap",34}, {"SteelScrap",42}, {"CopperScrap",38}, {"Aluminum",34},
    {"ElectronicsScrap",24}, {"CharcoalCrafted",28}, {"Coke",40}, {"GunPowder",65},

    {"Saw",58}, {"GardenSaw",52}, {"SmallSaw",48}, {"CrudeSaw",36},
    {"Screwdriver",34}, {"Pliers",42}, {"ViseGrips",48}, {"MetalworkingPliers",54},
    {"BoltCutters",72}, {"SheetMetalSnips",58}, {"SmallFileSet",62},
    {"SmallPunchSet",62}, {"Whetstone",48}, {"CrudeWhetstone",28},
    {"HandDrill",58}, {"OldDrill",62}, {"MeasuringTape",24}, {"Calipers",42},
    {"BlowTorch",85}, {"Bellows",110}, {"Tongs",54},
    {"BlacksmithAnvil",420}, {"BenchAnvil",260}, {"BlockAnvil",190}, {"StoneAnvil",145},

    {"Needle",18}, {"KnittingNeedles",24}, {"Thimble",16}, {"Awl",34},
    {"Paintbrush",20}, {"PlasterTrowel",38}, {"MasonsTrowel_Wood",28},
    {"Funnel",22}, {"RubberHose",30}, {"HeavyChain",65}, {"HeavyChain_Hook",78},

    {"PropaneTank",145, extraCategories={"other"}}, {"Battery",18}, {"BatteryBox",64},
    {"Generator",1200, extraCategories={"other"}},
    {"Generator_Blue",1200, extraCategories={"other"}},
    {"Generator_Old",1100, extraCategories={"other"}},
    {"Generator_Yellow",1300, extraCategories={"other"}},
    {"MotionSensor",58}, {"TimerCrafted",42}, {"TriggerCrafted",45},
    {"RadioReceiver",34}, {"RadioTransmitter",38}, {"Amplifier",36}, {"ScannerModule",44},
    {"LightBulb",14}, {"LightBulbBox",48}, {"HandTorch",38}, {"Torch",48},
    {"FlashLight_AngleHead",55}, {"Lantern_Hurricane",58}, {"Lantern_Propane",72},
    {"Candle",14}, {"CandleBox",45}, {"Matches",12}, {"Matchbox",14},
    {"Lighter",18}, {"LighterBBQ",22}, {"MagnesiumFirestarter",48},

    {"Tarp",38}, {"Sheet",24}, {"LeatherStrips",28}, {"DenimStrips",22},
    {"RippedSheets",16}, {"Claybag",48}, {"Dirtbag",38}, {"Gravelbag",42},
    {"Sandbag",42}, {"CompostBag",48}, {"Fertilizer",58},
    {"PlasterPowder",58}, {"WaterPurificationTablets",35},

    {"FishingRod",72}, {"CraftedFishingRod",52}, {"FishingLine",24},
    {"PremiumFishingLine",38}, {"FishingHook",16}, {"FishingHookBox",52},
    {"FishingNet",55}, {"JigLure",22}, {"MinnowLure",22},
    {"TrapBox",58}, {"TrapCage",62}, {"TrapCrate",52}, {"TrapSnare",38},
    {"CampingTentKit2_Packed",125}, {"SleepingBag_Green_Packed",72},
    {"CompassDirectional",45}, {"InsectRepellent",24},
})

-- Frequently required Build 42 workshop supplies that were missing from the
-- original pass. They remain resources first, while also being discoverable in
-- Other alongside the shop's maintenance and crafting equipment.
addItems("resource", "DescResource", "Recurso ou ferramenta", {
    {"AdhesiveTapeBox",95, extraCategories={"other"}},
    {"DuctTapeBox",110, extraCategories={"other"}},
    {"NailsCarton",260, extraCategories={"other"}},
    {"ScrewsCarton",280, extraCategories={"other"}},
    {"Hinge",18, extraCategories={"other"}},
    {"Doorknob",22, extraCategories={"other"}},
    {"Latch",20, extraCategories={"other"}},
    {"NutsBolts",28, extraCategories={"other"}},
    {"ScrapMetal",38, extraCategories={"other"}},
    {"CopperSheet",62, extraCategories={"other"}},
    {"SmallCopperSheet",36, extraCategories={"other"}},
    {"GlassPanel",72, extraCategories={"other"}},
    {"ConcretePowder",64, extraCategories={"other"}},
    {"Quicklime",52, extraCategories={"other"}},
    {"Clay",26, extraCategories={"other"}},
    {"ClayBrick",30, extraCategories={"other"}},
    {"Limestone",34, extraCategories={"other"}},
    {"LargeStone",28, extraCategories={"other"}},
    {"StoneBlock",48, extraCategories={"other"}},
    {"Twigs",12, extraCategories={"other"}},
    {"String",14, extraCategories={"other"}},
    {"Yarn",22, extraCategories={"other"}},
    {"SheetRope",24, extraCategories={"other"}},
    {"BurlapPiece",20, extraCategories={"other"}},
    {"FabricRoll_Cotton",75, extraCategories={"other"}},
    {"FabricRoll_DenimBlue",85, extraCategories={"other"}},
    {"Buckle",16, extraCategories={"other"}},
    {"Button",10, extraCategories={"other"}},
    {"CircularSawblade",74, extraCategories={"other"}},
    {"HacksawBlade",44, extraCategories={"other"}},
    {"CompassGeometry",34, extraCategories={"other"}},
    {"CrudeBenchVise",190, extraCategories={"other"}},
    {"ClayTool",38, extraCategories={"other"}},
    {"Fleshing_Tool",52, extraCategories={"other"}},
    {"HeadingTool",58, extraCategories={"other"}},
    {"KnappingTool",42, extraCategories={"other"}},
    {"Loupe",46, extraCategories={"other"}},
    {"OilPress",360, extraCategories={"other"}},
    {"SheepShears",62, extraCategories={"other"}},
    {"SheepElectricShears",110, extraCategories={"other"}},
    {"SteelWool",18, extraCategories={"other"}},
    {"StoneChisel",36, extraCategories={"other"}},
    {"StoneDrill",40, extraCategories={"other"}},
    {"HandFork",32, extraCategories={"other"}},
    {"HandShovel",42, extraCategories={"other"}},
    {"LeafRake",46, extraCategories={"other"}},
    {"Rake",54, extraCategories={"other"}},
    {"Scythe",145, extraCategories={"other"}},
    {"PowerBar",45, extraCategories={"other"}},
    {"HomeAlarm",70, extraCategories={"other"}},
    {"Receiver",36, extraCategories={"other"}},
    {"Remote",34, extraCategories={"other"}},
    {"Speaker",34, extraCategories={"other"}},
    {"BBQStarterFluid",34, extraCategories={"other"}},
    {"LighterFluid",28, extraCategories={"other"}},
    {"Propane_Refill",48, extraCategories={"other"}},
    {"CleaningLiquid2",24, extraCategories={"other"}},
    {"Bleach",28, extraCategories={"other"}},
    {"Soap2",18, extraCategories={"other"}},
    {"Sponge",14, extraCategories={"other"}},
    {"Brush",28, extraCategories={"other"}},
    {"AnimalFeedBag",68, extraCategories={"other"}},
    {"GrassBag",46, extraCategories={"other"}},
    {"GardeningSprayMilk",28, extraCategories={"other"}},
    {"GardeningSprayAphids",34, extraCategories={"other"}},
    {"GardeningSprayCigarettes",34, extraCategories={"other"}},
    {"SlugRepellent",36, extraCategories={"other"}},
    {"TrapMouse",30, extraCategories={"other"}},
    {"TrapStick",32, extraCategories={"other"}},
    {"PaintBlack",42, extraCategories={"other"}},
    {"PaintBlue",42, extraCategories={"other"}},
    {"PaintBrown",42, extraCategories={"other"}},
    {"PaintCyan",42, extraCategories={"other"}},
    {"PaintGreen",42, extraCategories={"other"}},
    {"PaintGrey",42, extraCategories={"other"}},
    {"PaintLightBlue",42, extraCategories={"other"}},
    {"PaintLightBrown",42, extraCategories={"other"}},
    {"PaintOrange",42, extraCategories={"other"}},
    {"PaintPink",42, extraCategories={"other"}},
    {"PaintPurple",42, extraCategories={"other"}},
    {"PaintRed",42, extraCategories={"other"}},
    {"PaintTurquoise",42, extraCategories={"other"}},
    {"PaintWhite",42, extraCategories={"other"}},
    {"PaintYellow",42, extraCategories={"other"}},
    {"SprayPaint",48, extraCategories={"other"}},
    {"TreeBranch2",16, extraCategories={"other"}},
    {"WoodenStick2",12, extraCategories={"other"}},
    {"LongStick",20, extraCategories={"other"}},
    {"LargeBranch",24, extraCategories={"other"}},
    {"Sapling",28, extraCategories={"other"}},
    {"Handle",24, extraCategories={"other"}},
    {"SmallHandle",18, extraCategories={"other"}},
    {"LongHandle",28, extraCategories={"other"}},
    {"Firewood",20, extraCategories={"other"}},
    {"FirewoodBundle",65, extraCategories={"other"}},
    {"SteelChunk",68, extraCategories={"other"}},
    {"SteelBarHalf",42, extraCategories={"other"}},
    {"SteelBarQuarter",28, extraCategories={"other"}},
    {"SteelRodHalf",40, extraCategories={"other"}},
    {"IronChunk",48, extraCategories={"other"}},
    {"IronBarHalf",38, extraCategories={"other"}},
    {"IronBarQuarter",24, extraCategories={"other"}},
    {"IronBlock",95, extraCategories={"other"}},
    {"SteelBlock",125, extraCategories={"other"}},
    {"IronPiece",26, extraCategories={"other"}},
    {"SteelPiece",32, extraCategories={"other"}},
    {"GoldScrap",55, extraCategories={"other"}},
    {"SilverScrap",48, extraCategories={"other"}},
    {"GoldSheet",110, extraCategories={"other"}},
    {"SilverSheet",95, extraCategories={"other"}},
    {"RailroadSpike",34, extraCategories={"other"}},
    {"TirePiece",25, extraCategories={"other"}},
    {"CeramicCrucible",80, extraCategories={"other"}},
    {"CeramicCrucibleSmall",55, extraCategories={"other"}},
    {"GlassBlowingPipe",75, extraCategories={"other"}},
    {"ClayBowl",20, extraCategories={"other"}},
    {"BucketEmpty",35, extraCategories={"other"}},
    {"BucketCarved",48, extraCategories={"other"}},
    {"PaperclipBox",35, extraCategories={"other"}},
    {"FlatStone",18, extraCategories={"other"}},
    {"Stone2",16, extraCategories={"other"}},
    {"SharpedStone",20, extraCategories={"other"}},
    {"AnimalBone",24, extraCategories={"other"}},
    {"SmallAnimalBone",18, extraCategories={"other"}},
    {"LargeAnimalBone",30, extraCategories={"other"}},
    {"Thread_Sinew",22, extraCategories={"other"}},
    {"Leather_Crude_Large_Tan",50, extraCategories={"other"}},
    {"Leather_Crude_Medium_Tan",40, extraCategories={"other"}},
    {"Leather_Crude_Small_Tan",30, extraCategories={"other"}},
    {"WoolRaw",26, extraCategories={"other"}},
    {"Dogbane",18, extraCategories={"other"}},
    {"Charcoal",28, extraCategories={"other"}},
    {"BarbedWireStack",120, extraCategories={"other"}},
    {"WireStack",90, extraCategories={"other"}},
    {"RopeStack",95, extraCategories={"other"}},
    {"SheetRopeBundle",80, extraCategories={"other"}},
    {"RippedSheetsBundle",60, extraCategories={"other"}},
    {"DenimStripsBundle",80, extraCategories={"other"}},
    {"LeatherStripsBundle",105, extraCategories={"other"}},
    {"PackFrame",55, extraCategories={"other"}},
    {"PackFrameLarge",75, extraCategories={"other"}},
})

-- Remaining practical crafting, camping, fishing and lighting supplies. These
-- are distinct functional tiers or recipe ingredients, not colour variants.
addItems("resource", "DescResource", "Recurso ou ferramenta", {
    {"BrassIngot",92, extraCategories={"other"}},
    {"AluminumScrap",34, extraCategories={"other"}},
    {"BrassScrap",40, extraCategories={"other"}},
    {"CheeseCloth",26, extraCategories={"other"}},
    {"IndustrialDye",34, extraCategories={"other"}},
    {"TarpPiece",16, extraCategories={"other"}},
    {"DentalFloss",14, extraCategories={"other"}},
    {"DrawPlate",75, extraCategories={"other"}},
    {"Sparklers",18, extraCategories={"other"}},
    {"SmokingPipe",24, extraCategories={"other"}},

    {"DryFirestarterBlock",20, extraCategories={"other"}},
    {"MagnesiumShavings",18, extraCategories={"other"}},
    {"PercedWood",22, extraCategories={"other"}},
    {"TwigsBundle",28, extraCategories={"other"}},
    {"HideTent_Packed",115, extraCategories={"other"}},
    {"ImprovisedTentKit_Packed",90, extraCategories={"other"}},
    {"SleepingBag_Cheap_Green_Packed",55, extraCategories={"other"}},
    {"SleepingBag_Hide_Packed",95, extraCategories={"other"}},
    {"SleepingBag_HighQuality_Brown_Packed",120, extraCategories={"other"}},

    {"Bobber",15, extraCategories={"other"}},
    {"Chum",20, extraCategories={"other"}},
    {"FishRoeSac",18, extraCategories={"other"}},
    {"FishGuts",12, extraCategories={"other"}},
    {"FishingHook_Bone",12, extraCategories={"other"}},
    {"FishingHook_Forged",22, extraCategories={"other"}},
    {"Flashlight_Crafted",32, extraCategories={"other"}},
    {"Lantern_CraftedElectric",48, extraCategories={"other"}},
    {"PenLight",28, extraCategories={"other"}},
    {"Awl_Bone",26, extraCategories={"other"}},
    {"Awl_Stone",24, extraCategories={"other"}},
    {"CrudeWoodenTongs",32, extraCategories={"other"}},
    {"Fleshing_Tool_Bone",38, extraCategories={"other"}},
    {"KnittingNeedles_Bone",18, extraCategories={"other"}},
    {"KnittingNeedles_Wood",18, extraCategories={"other"}},
    {"Needle_Bone",12, extraCategories={"other"}},
    {"Needle_Brass",22, extraCategories={"other"}},
    {"Needle_Forged",26, extraCategories={"other"}},
    {"PaintbrushCrafted",16, extraCategories={"other"}},
    {"SheepShearsForged",68, extraCategories={"other"}},
})

-- Practical treatment supplies and all medicinal plants. Dirty dressings,
-- cosmetic wound overlays and hospital props are not products.
addItems("medical", "DescMedical", "Suprimento médico", {
    {"Pills",30,"painkillers"}, {"PillsAntiDep",34}, {"PillsBeta",34},
    {"PillsSleepingTablets",36}, {"PillsVitamins",28},
    {"Antibiotics",78,"antibiotics"}, {"AntibioticsBox",190},
    {"Bandage",14,"bandages"}, {"BandageBox",72}, {"Bandaid",12},
    {"AdhesiveBandageBox",58}, {"AlcoholBandage",22}, {"AlcoholRippedSheets",18},
    {"AlcoholWipes",18}, {"AlcoholedCottonBalls",18}, {"CottonBalls",12},
    {"CottonBallsBox",45}, {"Disinfectant",38},
    {"Coldpack",20}, {"ColdpackBox",68}, {"Splint",28},
    {"SutureNeedle",48}, {"SutureNeedleBox",135}, {"SutureNeedleHolder",42},
    {"Tweezers",30}, {"ScissorsBluntMedical",38}, {"Scalpel",44},
    {"MortarPestle",45}, {"CeramicMortarandPestle",52},
    {"BlackSage",16}, {"BlackSageDried",18}, {"Comfrey",15}, {"ComfreyDried",17},
    {"CommonMallow",15}, {"CommonMallowDried",17}, {"Ginseng",20},
    {"Plantain",15}, {"PlantainDried",17}, {"WildGarlic2",18}, {"WildGarlicDried",20},
    {"ComfreyCataplasm",26}, {"PlantainCataplasm",26}, {"WildGarlicCataplasm",30},
})

addItems("medical", "DescMedical", "Suprimento médico", {
    {"Forceps_Forged",48}, {"Tweezers_Forged",34},
    {"Tissue",14}, {"TissueBox",42},
})

-- Not a real Build 42 item -- a synthetic "kind=cure" product. Purchasing it
-- does not spawn anything into the inventory; the server instead applies an
-- instant, absolute cure directly to the character (see LS.applyFullCure in
-- LasciviousShop_Server.lua): full health, every wound, the zombie virus
-- itself, sickness/poison/pain, fatigue and mood. Has no flat price -- see
-- LS.priceFor/LS.cureSeverity in LasciviousShop_Shared.lua: the price scales
-- with how badly hurt the character currently is, between LS.CURE_MIN_PRICE
-- and LS.CURE_MAX_PRICE.
table.insert(LS.PRODUCTS, {
    id="medical_full_cure", category="medical", kind="cure",
    skillIcon="full-cure", quantity=1,
    nameKey="ProductFullCure", fallback="Cura Total de Emergência",
    descKey="DescFullCure",
    descFallback="Cura instantânea e absoluta: remove o vírus zumbi, todos os ferimentos e doenças, e restaura sua saúde, fadiga e humor por completo. O preço varia com a gravidade do seu estado -- quanto pior, mais caro. Último recurso para não morrer.",
})

-- Protective clothing, carrying equipment and utility wear. Near-identical
-- colour variants are represented once; armor tiers and bag classes are not.
addItems("clothing", "DescClothing", "Vestuário ou equipamento", {
    {"Bag_FannyPackFront",32}, {"Bag_Satchel",58}, {"Bag_Schoolbag",65},
    {"Bag_DuffelBag",82}, {"Bag_NormalHikingBag",105}, {"Bag_BigHikingBag",145},
    {"Bag_ALICEpack",190}, {"Bag_SurvivorBag",190}, {"Bag_HydrationBackpack",135},
    {"Bag_ChestRig",115}, {"Bag_ALICE_BeltSus",105}, {"Bag_MedicalBag",90},
    {"Bag_ToolBag",82}, {"Bag_RifleCaseCloth",78}, {"Bag_RifleCase",115},
    {"Bag_CraftedFramepack_Small",85}, {"Bag_CraftedFramepack_Large",125},
    {"Bag_CraftedFramepack_Large2",155}, {"Bag_CraftedFramepack_Large3",180},

    {"HolsterAnkle",55}, {"HolsterSimple",68}, {"HolsterDouble",95}, {"HolsterShoulder",85},
    {"AmmoStrap_Bullets",62}, {"AmmoStrap_Shells",62},
    {"Vest_BulletCivilian",210}, {"Vest_BulletPolice",235},
    {"Vest_BulletArmy",270}, {"Vest_BulletSWAT",300},
    {"Cuirass_Magazine",130}, {"Cuirass_Wood",155}, {"Cuirass_Tire",180},
    {"Cuirass_Bone",205}, {"Cuirass_MetalScrap",265}, {"Cuirass_Metal",330},
    {"Cuirass_CoatOfPlates",390},

    {"Jacket_Leather",115}, {"Jacket_LeatherBlack",120},
    {"Jacket_ArmyOliveDrab",125}, {"Jacket_ArmyCamoGreen",130},
    {"Jacket_Police",135}, {"Jacket_Ranger",135}, {"Jacket_Fireman",175},
    {"Trousers_ArmyService",105},
    {"Trousers_Fireman",155}, {"Ghillie_Top",180}, {"Ghillie_Trousers",165},

    {"Shoes_ArmyBoots",95}, {"Shoes_WorkBoots",82}, {"Shoes_HikingBoots",88},
    {"Gloves_LeatherGloves",60}, {"Gloves_MetalScrapArmour",115}, {"Gloves_MetalArmour",145},
    {"Hat_HardHat",58}, {"Hat_Army",125}, {"Hat_RiotHelmet",155},
    {"Hat_CrashHelmetFULL",135}, {"Hat_SPHhelmet",175}, {"Hat_Fireman",145},
    {"Hat_GasMask",190}, {"WeldingMask",72},
})

-- Functional clothing expansion. It favours protection, weather resistance
-- and useful equipment over colour-only variants or purely cosmetic pieces.
addItems("clothing", "DescClothing", "Vestuário ou equipamento", {
    -- Face protection, respirators and replacement filters.
    {"Hat_DustMask",45}, {"Hat_SurgicalMask",28},
    {"Hat_BalaclavaFace",55}, {"Hat_BalaclavaFull",65},
    {"Hat_BandanaMask",26}, {"Hat_RagBandanaMask",20},
    {"ShemaghScarf",48}, {"ShemaghScarfFace",62},
    {"Hat_ShemaghFace",62}, {"Hat_ShemaghFull",75},
    {"Hat_BuildersRespirator",155}, {"Hat_ImprovisedGasMask",110},
    {"Hat_NBCmask",280}, {"GasmaskFilter",95},
    {"GasmaskFilterCrafted",75}, {"RespiratorFilters",75},
    {"RespiratorFiltersRecharged",90},

    -- Gloves and improvised hand protection, from utility to heavy armour.
    {"Gloves_Surgical",22}, {"Gloves_Dish",24},
    {"Gloves_FingerlessGloves",32}, {"Gloves_FingerlessLeatherGloves",52},
    {"Gloves_HuntingCamo",48}, {"Gloves_IceHockeyGloves",65},
    {"Gloves_RagWrap",24}, {"Gloves_BurlapWrap",28},
    {"Gloves_DenimWrap",34}, {"Gloves_TarpWrap",38},
    {"Gloves_LeatherWrap",62}, {"Gloves_BoneGloves",170},

    -- Eye, hearing, rain, cold and hazardous-environment protection.
    {"Glasses_SafetyGoggles",45}, {"Glasses_Shooting",55},
    {"Glasses_SkiGoggles",48}, {"Hat_EarMuff_Protectors",55},
    {"PonchoGreen",75}, {"PonchoTarp",65},
    {"Jacket_Padded",140}, {"Jacket_HuntingCamo",180},
    {"Jacket_CoatArmy",165}, {"Trousers_Padded",145},
    {"Trousers_LeatherCrafted",180}, {"Trousers_SheepSkin",170},
    {"Trousers_HuntingCamo",120}, {"Dungarees_HuntingCamo",145},
    {"Boilersuit",95}, {"Boilersuit_SWAT",145}, {"HazmatSuit",420},
    {"LongJohns",55}, {"LongJohns_Bottoms",38},

    -- Protective torso pieces and practical footwear.
    {"Apron_Leather",100}, {"Apron_Hide",80}, {"Apron_Tarp",60},
    {"Vest_Leather",110}, {"Vest_Hunting_Camo",85}, {"Vest_HighViz",45},
    {"Vest_Hide",75}, {"Vest_Tarp",58},
    {"Shoes_Wellies",120}, {"Shoes_CowboyBoots",100},
    {"Shoes_RidingBoots",105}, {"Shoes_HideBoots",95},
    {"Shoes_CrudeLeatherFootwear",70}, {"Shoes_TireSandals",55},

    -- Helmets and modular armour for limbs and shoulders.
    {"Hat_MetalHelmet",240}, {"Hat_MetalScrapHelmet",210},
    {"Hat_BicycleHelmet",80}, {"Hat_RidingHelmet",90},
    {"Hat_HockeyHelmet",105}, {"Hat_FootballHelmet",115},
    {"Hat_HardHat_Miner",75}, {"Hat_SWAT",180},
    {"Necklace_Choker_Bone",180},
    {"Vambrace_Leather_Left",75}, {"Vambrace_Leather_Right",75},
    {"Vambrace_FullMetal_Left",150}, {"Vambrace_FullMetal_Right",150},
    {"Vambrace_BodyArmour_Left_Army",190}, {"Vambrace_BodyArmour_Right_Army",190},
    {"GreaveBodyArmour_Left_Army",210}, {"GreaveBodyArmour_Right_Army",210},
    {"ThighBodyArmour_L_Army",220}, {"ThighBodyArmour_R_Army",220},
    {"Shoulderpad_Articulated_L_Metal",160}, {"Shoulderpad_Articulated_R_Metal",160},
    {"Shoulderpads_Football",125}, {"Shoulderpads_IceHockey",140},
})

-- Complete modular protection families. Left/right pieces are separate native
-- items because the game equips and damages each body side independently.
local modularProtection = {}
local function addProtection(itemId, price)
    table.insert(modularProtection, { itemId, price })
end
local function addProtectionPair(leftId, rightId, price)
    addProtection(leftId, price)
    addProtection(rightId, price)
end

addProtection("AthleticCup", 55)
addProtection("Codpiece_Leather", 85)
addProtection("Codpiece_Metal", 175)
addProtection("Cuirass_BasicBone", 185)
addProtection("IceHockeyNeckGuard", 58)
addProtection("SCBA", 390)
addProtection("Vest_CatcherVest", 115)
addProtectionPair("Chainmail_Hand_L", "Chainmail_Hand_R", 135)
addProtectionPair("Chainmail_SleeveFull_L", "Chainmail_SleeveFull_R", 245)
addProtectionPair("Gaiter_Left", "Gaiter_Right", 52)

addProtection("Gorget_Rag", 32)
addProtection("Gorget_Burlap", 38)
addProtection("Gorget_Denim", 55)
addProtection("Gorget_LeatherWrap", 72)
addProtection("Gorget_Leather", 88)
addProtection("Gorget_Metal", 175)

addProtectionPair("ElbowPad_Left", "ElbowPad_Right", 62)
addProtectionPair("Kneepad_Left", "Kneepad_Right", 68)
addProtectionPair("Shinpad_L", "Shinpad_R", 58)
addProtectionPair("Shinpad_L_Rigid", "Shinpad_R_Rigid", 82)
addProtectionPair("Shinpad_HockeyGoalie_L", "Shinpad_HockeyGoalie_R", 92)
addProtectionPair("ShinKneeGuard_L_Baseball", "ShinKneeGuard_R_Baseball", 88)
addProtectionPair("ShinKneeGuard_L_IceHockey", "ShinKneeGuard_R_IceHockey", 98)
addProtectionPair("ShinKneeGuard_L_Protective", "ShinKneeGuard_R_Protective", 115)
addProtectionPair("ShinKneeGuard_L_Metal", "ShinKneeGuard_R_Metal", 190)
addProtectionPair("ShinKneeGuardSpike_L_Baseball", "ShinKneeGuardSpike_R_Baseball", 112)
addProtectionPair("ShinKneeGuardSpike_L_IceHockey", "ShinKneeGuardSpike_R_IceHockey", 125)
addProtectionPair("ShinKneeGuardSpike_L_Protective", "ShinKneeGuardSpike_R_Protective", 145)
addProtectionPair("ShinKneeGuardSpike_L_Metal", "ShinKneeGuardSpike_R_Metal", 230)

addProtectionPair("GreaveMagazine_Left", "GreaveMagazine_Right", 72)
addProtectionPair("GreaveWood_Left", "GreaveWood_Right", 92)
addProtectionPair("GreaveTire_Left", "GreaveTire_Right", 108)
addProtectionPair("GreaveBone_Left", "GreaveBone_Right", 125)
addProtectionPair("GreaveScrap_Left", "GreaveScrap_Right", 150)
addProtectionPair("GreaveSpikeScrap_Left", "GreaveSpikeScrap_Right", 185)
addProtectionPair("Greave_Left", "Greave_Right", 205)
addProtectionPair("GreaveSpike_Left", "GreaveSpike_Right", 245)

addProtectionPair("VambraceMagazine_Left", "VambraceMagazine_Right", 68)
addProtectionPair("VambraceWood_Left", "VambraceWood_Right", 88)
addProtectionPair("VambraceTire_Left", "VambraceTire_Right", 102)
addProtectionPair("VambraceBone_Left", "VambraceBone_Right", 118)
addProtectionPair("VambraceScrap_Left", "VambraceScrap_Right", 142)
addProtectionPair("VambraceSpikeScrap_Left", "VambraceSpikeScrap_Right", 175)
addProtectionPair("Vambrace_Left", "Vambrace_Right", 195)
addProtectionPair("VambraceSpike_Left", "VambraceSpike_Right", 235)
addProtectionPair("Vambrace_LeatherSpike_Left", "Vambrace_LeatherSpike_Right", 105)

addProtectionPair("ThighMagazine_L", "ThighMagazine_R", 82)
addProtectionPair("ThighWood_L", "ThighWood_R", 98)
addProtectionPair("ThighTire_L", "ThighTire_R", 115)
addProtectionPair("ThighBone_L", "ThighBone_R", 135)
addProtectionPair("ThighProtective_L", "ThighProtective_R", 145)
addProtectionPair("ThighScrapMetal_L", "ThighScrapMetal_R", 165)
addProtectionPair("ThighScrapMetalSpike_L", "ThighScrapMetalSpike_R", 200)
addProtectionPair("ThighMetal_L", "ThighMetal_R", 220)
addProtectionPair("ThighMetalSpike_L", "ThighMetalSpike_R", 265)
addProtectionPair("Thigh_ArticMetal_L", "Thigh_ArticMetal_R", 285)

addProtectionPair("Shoulderpad_Wood_L", "Shoulderpad_Wood_R", 88)
addProtectionPair("Shoulderpad_Tire_L", "Shoulderpad_Tire_R", 102)
addProtectionPair("Shoulderpad_Bone_L", "Shoulderpad_Bone_R", 122)
addProtectionPair("Shoulderpad_Football_L", "Shoulderpad_Football_R", 78)
addProtectionPair("Shoulderpad_Football_Spiked_L", "Shoulderpad_Football_Spiked_R", 112)
addProtectionPair("Shoulderpad_MetalScrap_L", "Shoulderpad_MetalScrap_R", 148)
addProtectionPair("Shoulderpad_MetalSpikeScrap_L", "Shoulderpad_MetalSpikeScrap_R", 182)
addProtectionPair("Shoulderpad_Metal_L", "Shoulderpad_Metal_R", 205)
addProtectionPair("Shoulderpad_MetalSpike_L", "Shoulderpad_MetalSpike_R", 245)
addProtectionPair("Shoulderpad_ArticulatedSpike_L", "Shoulderpad_ArticulatedSpike_R", 195)

addProtection("Hat_BoneMask", 145)
addProtection("Hat_HockeyMask", 105)
addProtection("Hat_HockeyMask_Hide", 125)
addProtection("Hat_HockeyMask_MetalScrap", 175)
addProtection("Hat_HockeyMask_Metal", 220)
addProtection("Hat_CrashHelmetFULL_Spiked", 175)
addProtection("Jacket_Padded_HuntingCamo", 175)
addProtection("Trousers_Padded_HuntingCamo", 165)

addItems("clothing", "DescClothing", "Vestuário ou equipamento", modularProtection)

-- Functionally distinct carrying equipment overlooked by the first bag pass.
addItems("clothing", "DescClothing", "Vestuário ou equipamento", {
    {"Bag_ALICEpack_Army",220}, {"Bag_WeaponBag",130},
    {"Bag_FannyPackBack",32}, {"Bag_GolfBag",92},
    {"Bag_BurglarBag",155}, {"Bag_AmmoBox",105},
    {"Bag_TarpFramepack_Small",78}, {"Bag_TarpFramepack_Large",115},
})

-- Everyday civilian wardrobe. The first two passes leaned hard into protective
-- and functional gear; this fills the gap with the plain shirts, pants,
-- dresses and accessories players actually reach for outside combat.
addItems("clothing", "DescClothing", "Vestuário ou equipamento", {
    {"Tshirt_Sport",22}, {"Tshirt_WhiteLongSleeve",24}, {"Tshirt_BusinessSpiffo",28},
    {"Tshirt_SpiffoDECAL",26}, {"Tshirt_Ranger",24}, {"Tshirt_PoliceBlue",24},
    {"Tshirt_Sheriff",26}, {"Tshirt_Rock",20}, {"Tshirt_Metal",20},
    {"Tshirt_Punk",20}, {"Tshirt_HipHop",20}, {"Tshirt_Indie",20},
    {"Tshirt_CamoGreen",22}, {"Tshirt_ArmyGreen",22},

    {"Shirt_Denim",32}, {"Shirt_Lumberjack",34}, {"Shirt_FormalWhite",30},
    {"Shirt_Workman",28}, {"Shirt_OfficerWhite",32}, {"Shirt_PoliceBlue",30},
    {"Shirt_Sheriff",32}, {"Shirt_Priest",30},
    {"Shirt_HawaiianRed",28}, {"Shirt_Bowling_Blue",26}, {"Shirt_Bowling_White",26},
    {"Shirt_Baseball_KY",26}, {"Shirt_FormalWhite_ShortSleeve",28},

    {"Trousers_Denim",42}, {"Trousers_JeanBaggy",40}, {"Trousers_Black",36},
    {"Trousers_NavyBlue",36}, {"Trousers_Suit",55}, {"Trousers_SuitWhite",55},
    {"Trousers_Sport",34}, {"Trousers_Police",40}, {"Trousers_Sheriff",42},
    {"Trousers_Chef",34},
    {"Shorts_LongDenim",30}, {"Shorts_ShortDenim",26}, {"Shorts_LongSport",24},
    {"Shorts_ShortSport",22}, {"Shorts_ShortFormal",24},

    {"Dress_Knees",38}, {"Dress_Long",46}, {"Dress_Short",34},
    {"Dress_SmallStraps",40}, {"Dress_Normal",44},
    {"Skirt_Knees",32}, {"Skirt_Mini",26}, {"Skirt_Short",28},
    {"Skirt_Long",36}, {"Skirt_Normal",34},

    {"Jumper_RoundNeck",38}, {"Jumper_VNeck",38}, {"Jumper_PoloNeck",40},
    {"HoodieDOWN_WhiteTINT",45}, {"Hoodie_HuntingCamo_DOWN",52},
    {"Vest_DefaultTEXTURE",20}, {"Shirt_CropTopTINT",20},

    {"Suit_Jacket",90}, {"Suit_Jacket_White",95}, {"JacketLong_Black",85},
    {"JacketLong_Doctor",78}, {"WeddingJacket",70},
    {"Tie_Full",18}, {"Tie_BowTieFull",16}, {"Belt2",20},

    {"Hat_BaseballCap",22}, {"Hat_Beret",24}, {"Hat_Fedora",32},
    {"Hat_Fedora_Delmonte",38}, {"Hat_Spiffo",40},
    {"Glasses_Aviators",34}, {"Glasses_Sun",26}, {"Glasses_CatsEye_Sun",28},
    {"Gloves_LeatherGlovesBlack",32}, {"Gloves_LongWomenGloves",30},
    {"Gloves_FingerlessLeatherGloves_Black",34},
    {"Scarf_White",18}, {"Scarf_StripeBlackWhite",18},

    {"Necklace_Gold",45}, {"Necklace_Silver",30}, {"Necklace_Pearl",40},
    {"Necklace_Crucifix",26}, {"Locket",24}, {"Medal_Gold",20},

    {"Football_Jersey_White",30}, {"Football_Jersey_Black",30}, {"Ice_Hockey_Jersey_White",32},
    {"Boilersuit_Flying",85}, {"Boilersuit_Prisoner",60},
    {"Socks_Ankle_White",8}, {"Socks_Ankle_Black",8},
    {"Socks_Long_White",10}, {"Socks_Long_Black",10},

    {"Bra_Straps_Black",16}, {"Bra_Straps_White",16},
    {"Underpants_Black",12}, {"Underpants_White",12},
    {"Boxers_White",12}, {"Boxers_RedStripes",14}, {"Briefs_White",12},
    {"Corset_Black",45}, {"Corset_Red",45},
    {"Bikini_TINT",26}, {"Swimsuit_TINT",28}, {"SwimTrunks_Blue",22}, {"SwimTrunks_Red",22},
})

-- Military and hunting expansion (2026-08-21, explicit request: "principalmente
-- as militares, de caça"). Every camo pattern here has its OWN distinct
-- in-game display name (Desert/Green/Urban/Tiger Stripe/Foreign/Olive Drab),
-- unlike the melee "Forged" case fixed earlier -- so each is a genuine,
-- separate product, not a duplicate. Checked against every existing catalog
-- id's real display name first; a few near-identical vanilla variants WERE
-- true duplicates of items already in the catalog and were deliberately left
-- out: Vest_BulletDesert/DesertNew/OliveDrab (same name as Vest_BulletArmy),
-- Vambrace/ThighBodyArmour _Police/_SWAT (same name as the _Army versions
-- already listed), ElbowPad/Kneepad _Military/_Tactical (same name as the
-- plain pair already listed), Hat_ArmyDesert/ArmyDesertNew (same name as
-- Hat_Army), Hoodie_HuntingCamo_UP (same as the _DOWN already listed),
-- Jacket_Padded_HuntingCamoDOWN (same as Jacket_Padded_HuntingCamo).
addItems("clothing", "DescClothing", "Vestuário ou equipamento", {
    {"Hat_ArmyWWII",45}, {"Hat_BaseballCapArmy",26}, {"Hat_BaseballCap_HuntingCamo",26},
    {"Hat_BaseballCap_Police",26}, {"Hat_BaseballCap_SWAT",30}, {"Hat_BaseballHelmet_Rangers",55},
    {"Hat_BeretArmy",28}, {"Hat_BonnieHat_CamoGreen",32}, {"Hat_CrashHelmet_Police",145},
    {"Hat_PeakedCapArmy",38}, {"Hat_Police",45}, {"Hat_Police_Grey",45}, {"Hat_Ranger",34},

    {"Jacket_ArmyCamoDesertNew",135}, {"Jacket_ArmyCamoMilius",135},
    {"Jacket_ArmyCamoTigerStripe",135}, {"Jacket_ArmyCamoUrban",135},

    {"Shirt_CamoDesertNew",32}, {"Shirt_CamoGreen",32}, {"Shirt_CamoMilius",32},
    {"Shirt_CamoTigerStripe",32}, {"Shirt_CamoUrban",32}, {"Shirt_OliveDrab",32},
    {"Shirt_PoliceGrey",30}, {"Shirt_Ranger",30}, {"Shirt_Baseball_Rangers",26},

    {"Tshirt_CamoDesertNew",24}, {"Tshirt_CamoMilius",24}, {"Tshirt_CamoTigerStripe",24},
    {"Tshirt_CamoUrban",24}, {"Tshirt_OliveDrab",24}, {"Tshirt_PoliceGrey",22},
    {"Tshirt_HuntingCamo",24}, {"Tshirt_LongSleeve_HuntingCamo",26},
    {"Tshirt_Profession_PoliceBlue",22}, {"Tshirt_Profession_RangerBrown",22},

    {"Trousers_CamoDesertNew",110}, {"Trousers_CamoGreen",110}, {"Trousers_CamoMilius",110},
    {"Trousers_CamoTigerStripe",110}, {"Trousers_CamoUrban",110}, {"Trousers_OliveDrab",108},
    {"Trousers_PoliceGrey",40}, {"Trousers_Ranger",40},

    {"Shorts_CamoDesertNewLong",32}, {"Shorts_CamoGreenLong",32}, {"Shorts_CamoMiliusLong",32},
    {"Shorts_CamoTigerStripeLong",32}, {"Shorts_CamoUrbanLong",32}, {"Shorts_OliveDrabLong",30},

    {"Shoes_ArmyBootsDesert",98},

    {"Vest_Hunting_CamoGreen",85}, {"Vest_Hunting_Grey",85}, {"Vest_Hunting_Khaki",85},
    {"Vest_Hunting_Orange",90}, {"Vest_Trucker",78},
})

-- Wrist watches and pocketwatch, explicit request ("lembra de botar itens
-- como relógio"). Left/right wrist pieces are separate native items (same
-- pattern already used for Vambrace/Greave/Shoulderpad pairs above) because
-- a player can wear one on each wrist -- not duplicates. Only one colour per
-- style is kept (Classic Black over Brown, Digital Black over Red) since
-- those share the exact same in-game display name.
addItems("clothing", "DescClothing", "Vestuário ou equipamento", {
    {"WristWatch_Left_ClassicBlack",45}, {"WristWatch_Right_ClassicBlack",45},
    {"WristWatch_Left_ClassicGold",65}, {"WristWatch_Right_ClassicGold",65},
    {"WristWatch_Left_ClassicMilitary",55}, {"WristWatch_Right_ClassicMilitary",55},
    {"WristWatch_Left_DigitalBlack",30}, {"WristWatch_Right_DigitalBlack",30},
    {"WristWatch_Left_DigitalDress",42}, {"WristWatch_Right_DigitalDress",42},
    {"WristWatch_Left_Expensive",120}, {"WristWatch_Right_Expensive",120},
    {"Pocketwatch",55},
})

-- General wardrobe expansion ("outras também"): winter/cold-weather gear,
-- hide/leather craftables (pairs naturally with the hunting focus above),
-- jewellery, footwear variety and a few novelty/occasion pieces. Same
-- display-name collision check as above -- Holster (dup of HolsterSimple),
-- Boilersuit_PrisonerKhaki, Gloves_LeatherGlovesBrown, Jacket_Black/
-- LeatherBrown and Socks_Long/CowboyBoots_Black/Brown were all left out
-- because they share a display name with an item already in the catalog.
addItems("clothing", "DescClothing", "Vestuário ou equipamento", {
    {"Hat_DeerHeadress",45}, {"Hat_Beany",18}, {"Hat_BucketHat",20}, {"Hat_ChefHat",22},
    {"Hat_HeadSack_Burlap",24}, {"Hat_HeadSack_Cotton",26}, {"Hat_HeadSack_Hide",40},
    {"Hat_HeadSack_Garbage",14}, {"Hat_HeadSack_Tarp",28},
    {"Hat_Cowboy",45}, {"Hat_Cowboy_CowHide",65}, {"Hat_GolfHat",24}, {"Hat_HideHat",42},
    {"Hat_LeatherStripTied",20}, {"Hat_NewspaperHat",10}, {"Hat_Sheriff",38}, {"Hat_ShowerCap",8},
    {"Hat_Stovepipe",32}, {"Hat_SummerHat",20}, {"Hat_Sweatband",12}, {"Hat_TinFoilHat",10},
    {"Hat_WinterHat",26}, {"Hat_WinterHat_SheepSkin",48}, {"Hat_WoolyHat",24},
    {"Hat_SantaHat",22}, {"Hat_WeddingVeil",30}, {"Hat_EarMuffs",22},

    {"LongCoat_Bathrobe",35}, {"JacketLong_CowHide",145}, {"Jacket_CowHide",110},
    {"JacketLong_Hide",130}, {"Jacket_Hide",95}, {"LongCoat_Hide",120},
    {"Jacket_Chef",45}, {"Jacket_NavyBlue",65}, {"Jacket_Varsity",70}, {"Jacket_Leather_Punk",118},
    {"JacketLong_SheepSkin",150}, {"Jacket_SheepSkin",115}, {"Vest_SheepSkin",95},
    {"Jacket_Sheriff",95}, {"JacketLong_Santa",55}, {"Vest_Waistcoat",40}, {"Hoodie_Hide_DOWN",105},

    {"Trousers_DeerHide",85}, {"Trousers_Hide",78}, {"Trousers_LeatherBlack",90},
    {"TrousersMesh_Leather",92}, {"Trousers_Scrubs",32}, {"Trousers_PrisonGuard",38},
    {"Trousers_Santa",34}, {"Dungarees",42},

    {"Shirt_Scrubs",30}, {"Shirt_PrisonGuard",32}, {"Tshirt_Scrubs",24},

    {"Shoes_BlackBoots",55}, {"Shoes_Bowling",30}, {"Shoes_BurlapWrap",22}, {"Shoes_DenimWrap",26},
    {"Shoes_Fancy",65}, {"Shoes_FlipFlop",12}, {"Shoes_RagWrap",18}, {"Shoes_Sandals",24},
    {"Shoes_LeatherWrap",32}, {"Shoes_Slippers",14}, {"Shoes_BlueTrainers",40}, {"Shoes_Strapped",28},
    {"Shoes_TarpWrap",20}, {"Shoes_Twine",16}, {"Shoes_Black",35},
    {"Shoes_CowboyBoots_Fancy",130}, {"Shoes_CowboyBoots_SnakeSkin",145},

    {"Necklace_Choker",25}, {"Necklace_Choker_Diamond",65}, {"Necklace_GoldDiamond",70},
    {"Necklace_GoldRuby",65}, {"Necklace_SilverCrucifix",32}, {"Necklace_SilverDiamond",60},
    {"Necklace_SilverSapphire",58}, {"NecklaceLong_Gold",48}, {"NecklaceLong_Silver",34},
    {"Necklace_YingYang",22}, {"Necklace_BoarTusk",35}, {"Necklace_BoarTusk_Multi",48},
    {"Bracelet_BangleLeftGold",40}, {"Bracelet_BangleRightGold",40},
    {"Bracelet_ChainLeftSilver",30}, {"Bracelet_ChainRightSilver",30},
    {"Earring_LoopSmall_Gold_Top",28}, {"Earring_LoopSmall_Silver_Top",22},
    {"RopeBelt",12}, {"Holster_Hide",58},

    {"Apron_BBQ",24}, {"Apron_Black",20}, {"Apron_White",20}, {"WeddingDress",95},
    {"Vest_DeerHide",68}, {"Jacket_DeerHide",105}, {"Socks_Heavy",12},
})

-- Every Build 42 vehicle meant to be player-obtainable: every real, driveable
-- vehicle plus the towable trailers. Deliberately excludes the two families
-- of non-functional wrecks (burnt husks with no engine/wheels/seats at all,
-- and the pre-crashed "SmashedFront/Rear/Left/Right" shells vanilla's own
-- translations label "Wrecked <Name>", used only for scripted world-dressing
-- pileups) and two fully-modeled but unused prototype vehicles that appear in
-- none of the game's own spawn tables, zone definitions or mechanics UI and
-- have no in-game name -- not something a player has any lore-consistent way
-- to already know about. kind="vehicle": buying one does not add an
-- inventory item, the server spawns the real vehicle nearby (see
-- LS.applyFullCure's neighbour deliverVehicle in LasciviousShop_Server.lua
-- for the item/xp/cure equivalents -- vehicles get their own delivery path).
-- Pricing is tiered by real-world class and in-universe rarity/prestige, not
-- flat per category: liveried/business-branded variants of the exact same
-- mechanical vehicle (same template, same parts) share their base model's
-- price, since re-skinning changes nothing about what you're actually buying.
local function addVehicleProducts(price, entries)
    for _, entry in ipairs(entries) do
        local shortName = entry[1]
        table.insert(LS.PRODUCTS, {
            id="vehicle_" .. string.lower(shortName), category="vehicle", kind="vehicle",
            fullType="Base." .. shortName, quantity=1, price=entry[3] or price,
            skillIcon="car-solid",
            fallback=entry[2] or shortName,
            descKey="DescVehicle",
            descFallback="Veículo completo, entregue em condição perfeita e com o tanque cheio.",
        })
    end
end

-- Compacts, standard sedans, wagons and the flagship luxury car -- tiered
-- individually since "Sedan/Car" spans a much wider real-world price range
-- than any other single vehicle family.
addVehicleProducts(1900, {
    {"SmallCar", "Chevalier Dart"}, {"SmallCar02", "Masterson Horizon"},
})
addVehicleProducts(2000, {
    {"CarNormal", "Chevalier Nyala"}, {"CarTaxi", "Taxi"}, {"CarTaxi2", "Taxi"},
})
addVehicleProducts(2100, {
    {"CarStationWagon", "Chevalier Cerise Wagon"}, {"CarStationWagon2", "Chevalier Cerise Wagon"},
})
addVehicleProducts(2300, {
    {"ModernCar", "Dash Elite"}, {"ModernCar02", "Chevalier Primani"},
})
addVehicleProducts(2900, {
    {"CarLuxury", "Mercia Lang 4000"},
})

-- Sports and race cars: fast, rare, no practical cargo -- priced as a
-- prestige purchase.
addVehicleProducts(4200, {
    {"RaceCar12", "Race Car"}, {"RaceCar34", "Race Car"}, {"RaceCar58", "Race Car"},
    {"SportsCar", "Chevalier Cossette"},
})

-- SUV / off-road.
addVehicleProducts(3000, {
    {"OffRoad", "Dash Rancher"}, {"SUV", "Franklin All-Terrain"},
})

-- Ambulance: the single rarest civilian-service vehicle in the base game,
-- iconic and highly desirable.
addVehicleProducts(4500, {
    {"VanAmbulance", "Ambulance"},
})

-- Fire department livery: the rarest emergency-service vehicles in vanilla.
addVehicleProducts(4800, {
    {"PickUpTruckLightsFire", "Fire Department Chevalier D6"},
    {"PickUpVanLightsFire", "Fire Department Dash Bulldriver"},
})

-- Park ranger livery.
addVehicleProducts(3500, {
    {"CarLightsRanger", "Ranger Chevalier Nyala"},
    {"PickUpTruckLightsRanger", "Ranger Chevalier D6"},
    {"PickUpVanLightsRanger", "Ranger Dash Bulldriver"},
})

-- Police, sheriff, state trooper and SWAT liveries. The SWAT step van is
-- priced above the rest of the group -- bigger, rarer, more armoured feel.
addVehicleProducts(4000, {
    {"CarLightsBulletinSheriff", "Bulletin Sheriff Chevalier Nyala"},
    {"CarLightsKST", "State Trooper Chevalier Nyala"},
    {"CarLightsLouisvilleCounty", "LCPD Chevalier Nyala"},
    {"CarLightsMuldraughPolice", "Muldraugh Police Chevalier Nyala"},
    {"CarLightsPolice", "Police Chevalier Nyala"},
    {"ModernCarLightsCityLouisvillePD", "Louisville Police Dash Elite"},
    {"ModernCarLightsMeadeSheriff", "Meade Sheriff Dash Elite"},
    {"ModernCarLightsWestPoint", "West Point Police Dash Elite"},
    {"PickUpVanLightsLouisvilleCounty", "LCPD Dash Bulldriver"},
    {"PickUpVanLightsPolice", "Police Dash Bulldriver"},
    {"PickUpVanLightsStatePolice", "State Trooper Dash Bulldriver"},
    {"StepVan_LouisvilleSWAT", "Louisville SWAT Chevalier Step Van", 5200},
})

-- Pickup trucks: Chevalier D6 and Dash Bulldriver, every business livery and
-- the plain civilian/camo versions all share the same mechanical price.
addVehicleProducts(2600, {
    {"PickUpTruck", "Chevalier D6"},
    {"PickUpTruckJPLandscaping", "JP Landscaping Chevalier D6"},
    {"PickUpTruckLightsAirport", "Airport Chevalier D6"},
    {"PickUpTruckLightsAirportSecurity", "Airport Security Chevalier D6"},
    {"PickUpTruckLightsFossoil", "Fossoil Chevalier D6"},
    {"PickUpTruckMccoy", "McCoy Chevalier D6"},
    {"PickUpTruck_Camo", "Chevalier D6"},
    {"PickUpVan", "Dash Bulldriver"},
    {"PickUpVanBrickingIt", "Bricking It Dash Bulldriver"},
    {"PickUpVanBuilder", "Builder's Dash Bulldriver"},
    {"PickUpVanCallowayLandscaping", "Calloway Landscaping Dash Bulldriver"},
    {"PickUpVanHeltonMetalWorking", "Helton Metalworking Dash Bulldriver"},
    {"PickUpVanKimbleKonstruction", "Kimbler Konstruction Dash Bulldriver"},
    {"PickUpVanLightsCarpenter", "Carpenter's Dash Bulldriver"},
    {"PickUpVanLightsFossoil", "Fossoil Dash Bulldriver"},
    {"PickUpVanLightsKentuckyLumber", "Kentucky Lumber Dash Bulldriver"},
    {"PickUpVanMarchRidgeConstruction", "March Ridge Construction Dash Bulldriver"},
    {"PickUpVanMccoy", "McCoy Dash Bulldriver"},
    {"PickUpVanMetalworker", "Metalworker's Dash Bulldriver"},
    {"PickUpVanWeldingbyCamille", "Welding by Camille Dash Bulldriver"},
    {"PickUpVanYingsWood", "Van Yings Wood Dash Bulldriver"},
    {"PickUpVan_Camo", "Dash Bulldriver"},
})

-- Box trucks / cargo: the Chevalier Step Van family, every delivery/trade
-- livery. Large, slow, huge cargo capacity.
addVehicleProducts(3200, {
    {"StepVan", "Chevalier Step Van"},
    {"StepVanAirportCatering", "Airport Catering Chevalier Step Van"},
    {"StepVanMail", "Mail Chevalier Step Van"},
    {"StepVan_Blacksmith", "Chevalier Step Van"},
    {"StepVan_Butchers", "Chevalier Step Van"},
    {"StepVan_Cereal", "Cereal Delivery Chevalier Step Van"},
    {"StepVan_Citr8", "Citr8 Chevalier Step Van"},
    {"StepVan_CompleteRepairShop", "Complete Repair Shop Chevalier Step Van"},
    {"StepVan_Florist", "Chevalier Step Van"},
    {"StepVan_Genuine_Beer", "Genuine Beer Chevalier Step Van"},
    {"StepVan_Glass", "Chevalier Step Van"},
    {"StepVan_Heralds", "KY Herald Chevalier Step Van"},
    {"StepVan_HuangsLaundry", "Huang's Laundry Chevalier Step Van"},
    {"StepVan_Jorgensen", "Jorgensen Chevalier Step Van"},
    {"StepVan_LouisvilleMotorShop", "Louisville Motorshop Chevalier Step Van"},
    {"StepVan_MarineBites", "Marine Bites Chevalier Step Van"},
    {"StepVan_Masonry", "Chevalier Step Van"},
    {"StepVan_Mechanic", "Mechanic's Chevalier Step Van"},
    {"StepVan_MobileLibrary", "Chevalier Step Van"},
    {"StepVan_Plonkies", "Plonkies Chevalier Step Van"},
    {"StepVan_Propane", "Chevalier Step Van"},
    {"StepVan_RandisPlants", "Randi's Plants Chevalier Step Van"},
    {"StepVan_Scarlet", "Scarlet Oak Chevalier Step Van"},
    {"StepVan_SmartKut", "Chevalier Step Van"},
    {"StepVan_SouthEasternHosp", "South Eastern Hospitality Chevalier Step Van"},
    {"StepVan_SouthEasternPaint", "South Eastern Paint Chevalier Step Van"},
    {"StepVan_USL", "USL Chevalier Step Van"},
    {"StepVan_Zippee", "Zippee Chevalier Step Van"},
})

-- Vans: the Franklin Valuline family, every business livery plus the
-- passenger "Seats" variants and their novelty liveries.
addVehicleProducts(2400, {
    {"Van", "Franklin Valuline"},
    {"VanBeckmans", "Beckman's Building Franklin Valuline"},
    {"VanBrewsterHarbin", "Brewster & Harbin Franklin Valuline"},
    {"VanBuilder", "Builder's Franklin Valuline"},
    {"VanCarpenter", "Carpenter's Franklin Valuline"},
    {"VanCoastToCoast", "Coast 2 Coast Franklin Valuline"},
    {"VanDeerValley", "Deer Valley Power Franklin Valuline"},
    {"VanFossoil", "Fossoil Franklin Valuline"},
    {"VanGardenGods", "Garden Gods Franklin Valuline"},
    {"VanGardener", "Gardener's Franklin Valuline"},
    {"VanGreenes", "Greenes Franklin Valuline"},
    {"VanJohnMcCoy", "John McCoy Woodworking Franklin Valuline"},
    {"VanJonesFabrication", "Jones Fabrication Franklin Valuline"},
    {"VanKerrHomes", "Kerr Homes Franklin Valuline"},
    {"VanKnobCreekGas", "Knob Creek Gas Franklin Valuline"},
    {"VanKnoxCom", "Knox Telecommunications Franklin Valuline"},
    {"VanKorshunovs", "Korshunov's Car Center Franklin Valuline"},
    {"VanLouisvilleLandscaping", "Louisville Landscaping Franklin Valuline"},
    {"VanMail", "Mail Franklin Valuline"},
    {"VanMccoy", "McCoy Franklin Valuline"},
    {"VanMechanic", "Mechanic's Franklin Valuline"},
    {"VanMeltingPointMetal", "Melting Point Metal Franklin Valuline"},
    {"VanMetalheads", "Metalheads Franklin Valuline"},
    {"VanMetalworker", "Metalworker's Franklin Valuline"},
    {"VanMicheles", "Michele's Woodshop Franklin Valuline"},
    {"VanMobileMechanics", "Mobile Mechanics Franklin Valuline"},
    {"VanMooreMechanics", "Moore Mechanics Franklin Valuline"},
    {"VanOldMill", "Old Mill Water Company Franklin Valuline"},
    {"VanOvoFarm", "Franklin Valuline"},
    {"VanPennSHam", "Penn S. Ham Construction Franklin Valuline"},
    {"VanPlattAuto", "Platt Auto Repair Franklin Valuline"},
    {"VanPluggedInElectrics", "Plugged In Electrics Franklin Valuline"},
    {"VanRadio", "LBMW Radio Van"},
    {"VanRadio_3N", "Triple-N Van"},
    {"VanRiversideFabrication", "Riverside Fabrication Franklin Valuline"},
    {"VanRosewoodworking", "Rosewoodworking Franklin Valuline"},
    {"VanSchwabSheetMetal", "Schwab Sheet Metal Franklin Valuline"},
    {"VanSeats", "Franklin Valuline"},
    {"VanSeatsAirportShuttle", "Airport Franklin Valuline"},
    {"VanSeats_Creature", "Creature Cruiser"},
    {"VanSeats_LadyDelighter", "The Lady Delighter"},
    {"VanSeats_Mural", "Franklin Valuline"},
    {"VanSeats_Prison", "Prisoner Transport Franklin Valuline"},
    {"VanSeats_Space", "Quantum Vessel"},
    {"VanSeats_Trippy", "Mesmer Wagon"},
    {"VanSeats_Valkyrie", "Valkyrie's Spear"},
    {"VanSpiffo", "Spiffo Van"},
    {"VanTreyBaines", "Trey Baines Franklin Valuline"},
    {"VanUncloggers", "Uncloggers Franklin Valuline"},
    {"VanUtility", "Utility Franklin Valuline"},
    {"VanWPCarpentry", "WP Carpentry Franklin Valuline"},
    {"Van_Blacksmith", "Franklin Valuline"},
    {"Van_BugWipers", "Bug Wipers Franklin Valuline"},
    {"Van_Charlemange_Beer", "Franklin Valuline"},
    {"Van_CraftSupplies", "Franklin Valuline"},
    {"Van_Glass", "Franklin Valuline"},
    {"Van_HeritageTailors", "Franklin Valuline"},
    {"Van_KnoxDisti", "Knox Distillery Franklin Valuline"},
    {"Van_Leather", "Franklin Valuline"},
    {"Van_LectroMax", "Lectromax Franklin Valuline"},
    {"Van_Locksmith", "Franklin Valuline"},
    {"Van_Masonry", "Franklin Valuline"},
    {"Van_MassGenFac", "Mass GenFac Franklin Valuline"},
    {"Van_Perfick_Potato", "Franklin Valuline"},
    {"Van_Transit", "Transit Franklin Valuline"},
    {"Van_VoltMojo", "Volt Mojo Franklin Valuline"},
})

-- Trailers: towed only, no engine of their own -- priced well below any
-- powered vehicle, but never below the shop-wide 1000 credit floor. The
-- livestock/horse trailers are a step above the plain cargo trailers for
-- their specialised purpose.
addVehicleProducts(1000, {
    {"Trailer", "Trailer"}, {"TrailerAdvert", "Trailer"}, {"TrailerCover", "Trailer"},
})
addVehicleProducts(1300, {
    {"Trailer_Horsebox", "Horse trailer"}, {"Trailer_Livestock", "Livestock Trailer"},
})

-- Firearm attachments, explosives, books, seeds, culinary equipment and
-- special-purpose survival gear that does not fit one of the core categories.
addItems("other", "DescTobacco", "Tabaco ou acessório para fumar", {
    {"CigaretteSingle",4}, {"CigaretteRolled",4},
    {"CigarettePack",55}, {"CigaretteCarton",480},
    {"Cigarillo",10}, {"Cigar",18}, {"TobaccoChewing",42},
    {"TobaccoLoose",48}, {"CigaretteRollingPapers",24},
    {"SmokingPipe_Tobacco",34}, {"CanPipe_Tobacco",30},
    {"Tobacco",18}, {"TobaccoDried",22},
    {"LighterDisposable",16}, {"Lighter_Battery",22},
})

addItems("ammo", "DescWeaponPart", "Acessório para arma", {
    {"AmmoStraps",70}, {"ChokeTubeFull",55}, {"ChokeTubeImproved",55},
    {"GunLight",75}, {"Laser",120}, {"RecoilPad",65}, {"RedDot",130},
    {"TritiumSights",100}, {"x2Scope",100}, {"x4Scope",150}, {"x8Scope",220},
})

addItems("other", "DescExplosive", "Explosivo ou dispositivo", {
    {"Firecracker",18}, {"Firecracker_Crafted",15}, {"Molotov",90},
    {"Aerosolbomb",125}, {"AerosolbombTriggered",140}, {"AerosolbombRemote",155},
    {"AerosolbombSensorV1",150}, {"AerosolbombSensorV2",165}, {"AerosolbombSensorV3",180},
    {"PipeBomb",185}, {"PipeBombTriggered",200}, {"PipeBombRemote",220},
    {"PipeBombSensorV1",215}, {"PipeBombSensorV2",235}, {"PipeBombSensorV3",255},
    {"FlameTrap",230}, {"FlameTrapTriggered",245}, {"FlameTrapRemote",270},
    {"FlameTrapSensorV1",265}, {"FlameTrapSensorV2",285}, {"FlameTrapSensorV3",305},
    {"SmokeBomb",65}, {"SmokeBombTriggered",75}, {"SmokeBombRemote",85},
    {"SmokeBombSensorV1",82}, {"SmokeBombSensorV2",92}, {"SmokeBombSensorV3",102},
    {"NoiseTrap",70}, {"NoiseTrapTriggered",80}, {"NoiseTrapRemote",90},
    {"NoiseTrapSensorV1",88}, {"NoiseTrapSensorV2",98}, {"NoiseTrapSensorV3",108},
})

addItems("other", "DescKitchen", "Utensílio culinário", {
    {"BakingPan",34}, {"BakingTray",34}, {"BastingBrush",18}, {"BakingSoda",16},
    {"BottleOpener",18}, {"Bowl",16}, {"BoxOfJars",75}, {"CheeseGrater",24},
    {"Corkscrew",20}, {"CuttingBoardPlastic",22}, {"CuttingBoardWooden",22},
    {"EmptyJar",18}, {"JarLid",12}, {"GrillBrush",22}, {"Kettle",34},
    {"Kettle_Copper",42}, {"KitchenTongs",22}, {"Ladle",20}, {"MuffinTray",30},
    {"OvenMitt",20}, {"P38",24}, {"PizzaCutter",22}, {"Pot",42}, {"PotForged",50},
    {"RoastingPan",38}, {"SkewersWooden",18}, {"Spatula",20}, {"Strainer",22},
    {"Timer",24}, {"TinOpener",26}, {"Whisk",20}, {"WoodenSpoon",16},
    {"JarCrafted",20}, {"BottleOpener_Keychain",22},
})

local seedBagEntries = {}
local seedBagIds = {
    "BarleyBagSeed", "BasilBagSeed", "BellPepperBagSeed", "BlackSageBagSeed",
    "BroadleafPlantainBagSeed", "BroccoliBagSeed2", "CabbageBagSeed2", "CarrotBagSeed2",
    "CauliflowerBagSeed", "ChamomileBagSeed", "ChivesBagSeed", "CilantroBagSeed",
    "ComfreyBagSeed", "CommonMallowBagSeed", "CornBagSeed", "CucumberBagSeed",
    "FlaxBagSeed", "GarlicBagSeed", "GreenpeasBagSeed", "HabaneroBagSeed",
    "HempBagSeed", "HopsBagSeed", "JalapenoBagSeed", "KaleBagSeed",
    "LavenderBagSeed", "LeekBagSeed", "LemonGrassBagSeed", "LettuceBagSeed",
    "MarigoldBagSeed", "MintBagSeed", "OnionBagSeed", "OreganoBagSeed",
    "ParsleyBagSeed", "PoppyBagSeed", "PotatoBagSeed2", "PumpkinBagSeed",
    "RedRadishBagSeed2", "RoseBagSeed", "RosemaryBagSeed", "RyeBagSeed",
    "SageBagSeed", "SoybeansBagSeed", "SpinachBagSeed", "StrewberrieBagSeed2",
    "SugarBeetBagSeed", "SunflowerBagSeed", "SweetPotatoBagSeed", "ThymeBagSeed",
    "TobaccoBagSeed", "TomatoBagSeed2", "TurnipBagSeed", "WatermelonBagSeed",
    "WheatBagSeed", "WildGarlicBagSeed", "ZucchiniBagSeed",
}
for _, itemId in ipairs(seedBagIds) do table.insert(seedBagEntries, { itemId, 30 }) end
addItems("other", "DescSeed", "Pacote de sementes", seedBagEntries)

local skillBookPrices = { 28, 44, 64, 88, 118 }
local skillBookSeries = {
    {"Aiming", "BookAimingSet"}, {"Blacksmith", "BookBlacksmithSet"},
    {"Butchering", "BookButcheringSet"}, {"Carpentry", "BookCarpentrySet"},
    {"Carving", "BookCarvingSet"}, {"Cooking", "BookCookingSet"},
    {"Electrician", "BookElectricianSet"}, {"Farming", "BookFarmingSet"},
    {"FirstAid", "BookFirstAidSet"}, {"Fishing", "BookFishingSet"},
    {"FlintKnapping", "BookFlintKnappingSet"}, {"Foraging", "BookForagingSet"},
    {"Glassmaking", "BookGlassmakingSet"}, {"Husbandry", "BookHusbandrySet"},
    {"LongBlade", "BookLongBladeSet"}, {"Maintenance", "BookMaintenanceSet"},
    {"Masonry", "BookMasonrySet"}, {"Mechanic", "BookMechanicsSet"},
    {"MetalWelding", "BookMetalWeldingSet"}, {"Pottery", "BookPotterySet"},
    {"Reloading", "BookReloadingSet"}, {"Tailoring", "BookTailoringSet"},
    {"Tracking", "BookTrackingSet"}, {"Trapping", "BookTrappingSet"},
}
for _, series in ipairs(skillBookSeries) do
    local volumeEntries = {}
    for volume = 1, 5 do
        table.insert(volumeEntries, { "Book" .. series[1] .. tostring(volume), skillBookPrices[volume] })
    end
    addItems("other", "DescSkillBook", "Livro de habilidade", volumeEntries)
    addItems("other", "DescBookSet", "Conjunto completo de livros", {
        { series[2], 420 },
    })
end

-- Recipe magazines are separate from skill books in Build 42: they unlock
-- recipes instead of multiplying XP. Every useful vanilla recipe magazine is
-- included so rare knowledge is not an accidental hole in the shop.
local recipeMagazineEntries = {
    {"HempMag1", 75}, {"HerbalistMag", 90}, {"KeyMag1", 75},
    {"ArmorSchematic", 105}, {"BSToolsSchematic", 105},
    {"CookwareSchematic", 105}, {"ExplosiveSchematic", 125},
    {"MeleeWeaponSchematic", 120}, {"SewingPattern", 95},
    {"SurvivalSchematic", 110},
}
local recipeMagazineSeries = {
    {"ArmorMag", 7}, {"CookingMag", 6}, {"ElectronicsMag", 5},
    {"EngineerMagazine", 3}, {"FarmingMag", 9}, {"FishingMag", 2},
    {"GlassmakingMag", 3}, {"HuntingMag", 4}, {"KnittingMag", 2},
    {"MechanicMag", 3}, {"MetalworkMag", 4}, {"PrimitiveToolMag", 3},
    {"RadioMag", 3}, {"SmithingMag", 11}, {"TailoringMag", 10},
    {"TrickMag", 2}, {"WeaponMag", 7},
}
for _, series in ipairs(recipeMagazineSeries) do
    for volume = 1, series[2] do
        table.insert(recipeMagazineEntries, { series[1] .. tostring(volume), 75 })
    end
end
addItems("other", "DescRecipeMagazine", "Revista de receitas", recipeMagazineEntries)

addItems("other", "DescSpecial", "Equipamento especial", {
    {"PetrolCan",260}, {"JerryCan",480},
    {"CarBatteryCharger",220}, {"Jack",95}, {"LugWrench",72}, {"TirePump",65},
    {"EngineParts",24}, {"CarBattery1",210}, {"CarBattery2",230}, {"CarBattery3",250},
    {"Extinguisher",150}, {"CombinationPadlock",65}, {"Padlock",45},
    {"Canteen",55}, {"CanteenMilitary",80}, {"CanteenMilitaryFull",95},
    {"Sportsbottle",35}, {"WaterDispenserBottle",90}, {"WateredCan",45}, {"Bucket",42},
    {"Garbagebag",28}, {"Toolbox",75}, {"FirstAidKit",85}, {"SewingKit",65},
    {"Scissors",28}, {"RadioBlack",55}, {"RadioRed",70},
    {"WalkieTalkie2",65}, {"WalkieTalkie3",90}, {"WalkieTalkie4",130},
    {"WalkieTalkie5",170}, {"HamRadio1",210}, {"HamRadio2",300}, {"ManPackRadio",360},
})

-- Practical utility, communication, navigation and recreation. Generic keys,
-- random prefilled media and decorative electronics are deliberately omitted.
addItems("other", "DescSpecial", "Equipamento especial", {
    {"WalkieTalkie1",48}, {"WalkieTalkieMakeShift",42},
    {"RadioMakeShift",45}, {"HamRadioMakeShift",175},
    {"CDplayer",55}, {"Earbuds",18}, {"Headphones",24}, {"VideoGame",35},
    {"RemoteCraftedV1",38}, {"RemoteCraftedV2",48}, {"RemoteCraftedV3",58},
    {"Bullhorn",75}, {"AlarmClock2",32}, {"BathTowel",18},
    {"RatPoison",28}, {"MagnifyingGlass",25}, {"UmbrellaBlack",38},
    {"ScissorsBlunt",22}, {"BottleCrafted",20}, {"HotWaterBottle",32},
    {"CardDeck",18}, {"Dice",16},
})

addItems("other", "DescEntertainment", "Leitura ou entretenimento", {
    {"Book",22}, {"ComicBook",16}, {"Magazine",14}, {"Newspaper",12},
})

addItems("other", "DescMap", "Mapa regional", {
    {"LouisvilleMap1",28}, {"LouisvilleMap2",28}, {"LouisvilleMap3",28},
    {"LouisvilleMap4",28}, {"LouisvilleMap5",28}, {"LouisvilleMap6",28},
    {"LouisvilleMap7",28}, {"LouisvilleMap8",28}, {"LouisvilleMap9",28},
    {"MarchRidgeMap",25}, {"MuldraughMap",25}, {"RiversideMap",25},
    {"RosewoodMap",25}, {"WestpointMap",25},
})

-- Complete useful replacement-part matrix for standard, heavy-duty and sport
-- vehicles. Cosmetic hood ornaments are the only VehicleMaintenance entries
-- intentionally omitted.
addItems("other", "DescVehiclePart", "Peça automotiva", {
    {"OldTire1",115}, {"NormalTire1",190}, {"ModernTire1",310},
    {"OldTire2",125}, {"NormalTire2",205}, {"ModernTire2",330},
    {"OldTire3",135}, {"NormalTire3",220}, {"ModernTire3",350},
    {"OldBrake1",95}, {"NormalBrake1",155}, {"ModernBrake1",245},
    {"OldBrake2",105}, {"NormalBrake2",165}, {"ModernBrake2",260},
    {"OldBrake3",115}, {"NormalBrake3",180}, {"ModernBrake3",280},
    {"NormalSuspension1",170}, {"ModernSuspension1",270},
    {"NormalSuspension2",185}, {"ModernSuspension2",290},
    {"NormalSuspension3",200}, {"ModernSuspension3",315},
    {"OldCarMuffler1",90}, {"NormalCarMuffler1",150}, {"ModernCarMuffler1",235},
    {"OldCarMuffler2",100}, {"NormalCarMuffler2",165}, {"ModernCarMuffler2",255},
    {"OldCarMuffler3",110}, {"NormalCarMuffler3",180}, {"ModernCarMuffler3",275},
    {"SmallGasTank1",175}, {"NormalGasTank1",265}, {"BigGasTank1",390},
    {"SmallGasTank2",190}, {"NormalGasTank2",285}, {"BigGasTank2",420},
    {"SmallGasTank3",205}, {"NormalGasTank3",305}, {"BigGasTank3",450},
    {"SmallTrunk1",150}, {"NormalTrunk1",225}, {"BigTrunk1",330}, {"TrailerTrunk1",300},
    {"SmallTrunk2",165}, {"NormalTrunk2",245}, {"BigTrunk2",355}, {"TrailerTrunk2",325},
    {"SmallTrunk3",180}, {"NormalTrunk3",265}, {"BigTrunk3",380}, {"TrailerTrunk3",350},
    {"NormalCarSeat1",135}, {"NormalCarSeat2",150}, {"NormalCarSeat3",165},
    {"VanSeatsTrunk2",220},
    {"EngineDoor1",250}, {"EngineDoor2",270}, {"EngineDoor3",290},
    {"TrunkDoor1",220}, {"TrunkDoor2",240}, {"TrunkDoor3",260},
    {"FrontCarDoor1",190}, {"FrontCarDoor2",205}, {"FrontCarDoor3",220},
    {"RearCarDoor1",180}, {"RearCarDoor2",195}, {"RearCarDoor3",210},
    {"RearCarDoorDouble1",260}, {"RearCarDoorDouble2",280}, {"RearCarDoorDouble3",300},
    {"FrontWindow1",105}, {"FrontWindow2",115}, {"FrontWindow3",125},
    {"RearWindow1",95}, {"RearWindow2",105}, {"RearWindow3",115},
    {"Windshield1",155}, {"Windshield2",170}, {"Windshield3",185},
    {"RearWindshield1",135}, {"RearWindshield2",150}, {"RearWindshield3",165},
    {"GloveBox1",85}, {"GloveBox2",95}, {"GloveBox3",105},
    {"LightbarBlue",180}, {"LightbarRed",180},
    {"LightbarRedBlue",210}, {"LightbarYellow",170},
})

-- Empty portable containers only. Prefilled loot variants are excluded so a
-- container purchase never becomes an undocumented bundle of free supplies.
addItems("other", "DescContainer", "Recipiente ou bolsa", {
    {"Cooler",95}, {"Briefcase",65}, {"Suitcase",100}, {"Lunchbox",42},
    {"Tacklebox",75}, {"Flightcase",110}, {"SeedBag",48}, {"EmptySandbag",24},
    {"ToolRoll_Fabric",58}, {"ToolRoll_Leather",82},
    {"Toolbox_Farming",82}, {"Toolbox_Fishing",82},
    {"Toolbox_Gardening",82}, {"Toolbox_Wooden",72}, {"Toolbox_Mechanic",105},
    {"Bag_ProtectiveCaseSmall",90}, {"Bag_ProtectiveCase",125},
    {"Bag_ProtectiveCaseMilitary",165}, {"Bag_ProtectiveCaseBulky",190},
    {"Bag_Gunny",46}, {"Bag_HideSack",62}, {"Bag_TarpSack",58},
    {"Bag_FishingBasket",75}, {"Bag_GardenBasket",70}, {"Bag_PicnicBasket",65},
    {"Bag_Satchel_Leather",90}, {"Bag_Military",170}, {"Bag_Police",150},
    {"Bag_SWAT",190}, {"Bag_WorkerBag",95},
    {"Bag_LeatherWaterBag",75}, {"CanteenClay",50}, {"CanteenCowboy",65},
    {"BucketForged",62}, {"BucketWood",48}, {"BucketLargeWood",68},
    {"KeyRing",18}, {"KeyRing_Large",28}, {"Cashbox",55},
    {"Humidor",52}, {"CigarBox",28},
})

-- Build 42 generated moveables: every entry below is a native, collectible
-- single inventory item with its own WorldObjectSprite. The player receives it
-- in the inventory and places it through the vanilla furniture tool.
addItems("furniture", "DescAppliance", "Eletrodoméstico posicionável", {
    {"Mov_BlueFridge",680}, {"Mov_FridgeMini",480}, {"Mov_GreenFridge",680},
    {"Mov_IndustrialFridge",950}, {"Mov_PlainFridge",620}, {"Mov_RedFridge",680},
    {"Mov_SteelFridge",760}, {"Mov_TrailerFridge",520}, {"Mov_WhiteFridge",650},
    {"Mov_WhiteIndustrialFridge",950}, {"Mov_ChestFreezer",850},
    {"Mov_PopsicleFreezer",900},
    {"Mov_AntiqueStove",1100}, {"Mov_GreenOven",580}, {"Mov_GreyOven",580},
    {"Mov_IndustrialOven",980}, {"Mov_ModernOven",720}, {"Mov_RedOven",580},
    {"Mov_Microwave",320}, {"Mov_Microwave2",340}, {"Mov_CoffeeMaker",180},
    {"Mov_Toaster",140}, {"Mov_BlackBBQ",390}, {"Mov_RedBBQ",390},
    {"Mov_WaterDispenser",460}, {"Mov_Lamp1",85}, {"Mov_Lamp2",85},
    {"Mov_Lamp3",90}, {"Mov_Lamp4",90}, {"Mov_Lamp5",95}, {"Mov_Lamp6",95},
})

addItems("furniture", "DescFurniture", "Móvel posicionável", {
    {"Mov_Cot",260}, {"Mov_CardboardBox",90}, {"Mov_CabinetTool",340},
    {"Mov_CabinetMedical",360}, {"Mov_FirstAidCabinet",330},
    {"Mov_MilitaryCrate",520}, {"Mov_SmallChest",280}, {"Mov_MetalLocker",480},
    {"Mov_GreenWallLocker",430}, {"Mov_BlueWallLocker",430},
    {"Mov_YellowWallLocker",430}, {"Mov_MetalWallShelves",360},
    {"Mov_OakShelves",310}, {"Mov_WoodPegboard",220},
    {"Mov_StandingVault",1800}, {"Mov_DarkGreenBarrel",260},
    {"Mov_RaisedPlantbed",260},
})

addItems("furniture", "DescCraftingStation", "Estação de trabalho posicionável", {
    {"Mov_BenchGrinder",720}, {"Mov_ConcreteMixer",950},
    {"Mov_ElectricBlowerForge",1400}, {"Mov_KeyDuplicator",900},
    {"Mov_WashingBin",420},
})

-- Construção/Moveables expansion (2026-08-21, request: "adicionando TODAS as
-- coisas que o jogador já é permitido construir no CONSTRUÇÃO que não são
-- estruturais"). Every non-structural, non-material Mov_* moveable in the game --
-- the full Furniture/Camping/Gardening pool minus the handful already listed above --
-- checked against the catalog's existing display names first (2 were true duplicates
-- and excluded: the abstract "Moveable" template with no real name, and
-- Mov_ConcreteRoadBlock, which shares its in-game name "Mortar Grinder" with
-- Mov_ConcreteMixer already above).
--
-- 2026-08-21 follow-up trim: the first pass included every non-structural moveable,
-- which meant a lot of purely decorative set-dressing with zero gameplay function got
-- in too (paintings/posters/curtains/mirrors/skulls/flags, arcade machines/phones/
-- computers/security terminals, commercial food-service props like an industrial
-- dishwasher, decorative houseplants, gravestones, signage, mannequins...). Checked
-- each removed category against the real game Lua (jar/script search) -- e.g. Air
-- Conditioner, Scarecrow and Salt Lick only ever show up in loot tables and
-- translation files, never in any interactive gameplay code, confirming they are
-- purely cosmetic like the rest. What is left below are the categories with real,
-- provable utility: seating, tables, storage (counters/drawers/cabinets/shelves),
-- bathroom fixtures, standalone containers (barrels/bins), outdoor lighting, and
-- camping gear.

-- Assentos: cadeiras, bancos, banquinhos e um pufe.
addItems("furniture", "DescFurniture", "Móvel posicionável", {
    {"Mov_BacklessWoodenBench",150}, {"Mov_BeachChair",105}, {"Mov_BlueComfyChair",175},
    {"Mov_BluePlasticChair",115}, {"Mov_BlueRattanChair",175}, {"Mov_BrownComfyChair",175},
    {"Mov_DarkBlueChair",115}, {"Mov_DarkWoodenChair",115}, {"Mov_DrumStool",95},
    {"Mov_FancyBlackChair",175}, {"Mov_FancyWhiteChair",175}, {"Mov_FoldingChair",115},
    {"Mov_GreenChair",115}, {"Mov_GreenComfyChair",175}, {"Mov_GreyChair",115},
    {"Mov_GreyComfyChair",175}, {"Mov_MetalStool",95}, {"Mov_OakBench",150},
    {"Mov_OfficeChair",160}, {"Mov_OrangeFuton",230}, {"Mov_OrangeModernChair",115},
    {"Mov_PileOCrepeChair",115}, {"Mov_PlasticChair",115}, {"Mov_PurpleRattanChair",175},
    {"Mov_PurpleWoodenChair",115}, {"Mov_RedChair",115}, {"Mov_RedWoodenChair",115},
    {"Mov_WhiteComfyChair",175}, {"Mov_WhiteSimpleChair",115}, {"Mov_WhiteWoodenChair",115},
    {"Mov_WoodenChair",115}, {"Mov_WoodenStool",95}, {"Mov_YellowModernChair",115},
})

-- Mesas.
addItems("furniture", "DescFurniture", "Móvel posicionável", {
    {"Mov_BlackLowModernTable",160}, {"Mov_BrownLowTable",160}, {"Mov_FancyDarkTable",290},
    {"Mov_FancyLowTable",290}, {"Mov_FancyTable",290}, {"Mov_LightRoundTable",225},
    {"Mov_LongTable",225}, {"Mov_OakRoundTable",225}, {"Mov_PlasticLowTable",160},
    {"Mov_RoundTable",225}, {"Mov_SmallTable",160},
})

-- Armazenamento: balcões de loja, cômodas, armários e prateleiras. The extra
-- entries below (drawers with mirror, cash registers, clothes stand, mail
-- boxes, vegetable basket, doghouse) were part of the original "purely
-- decorative" trim on 2026-08-21 but got re-checked directly against the
-- game's real tile definitions (media/newtiledefinitions.tiles.txt) after a
-- follow-up question -- every one of them has a real ContainerCapacity/
-- container field there, so they DO function as containers in-game despite
-- looking cosmetic by name/category. See the note further below for the
-- full verification method.
addItems("furniture", "DescFurniture", "Móvel posicionável", {
    {"Mov_BirchCornerCounter",260}, {"Mov_BirchCounter",260}, {"Mov_BirchDrawers",265},
    {"Mov_BirchDrawersMirror",265}, {"Mov_BlackCashRegister",190}, {"Mov_CashRegister",190},
    {"Mov_ClothesStand",90}, {"Mov_ComicsShopShelves",310}, {"Mov_DarkCornerCounter",260},
    {"Mov_DarkCounter",260}, {"Mov_DarkFancyDrawers",265}, {"Mov_Doghouse",150},
    {"Mov_FancyChestnutDrawers",265}, {"Mov_FloatingTrailerCounter",260}, {"Mov_GreenCornerCounter",260},
    {"Mov_GreenCounter",260}, {"Mov_Mailbox",75}, {"Mov_MilitaryLocker",460},
    {"Mov_MobileCounter",260}, {"Mov_ModernCornerCounter",260}, {"Mov_ModernCounter",260},
    {"Mov_OakCornerCounter",260}, {"Mov_OakCounter",260}, {"Mov_PineCornerCounter",260},
    {"Mov_PineCounter",260}, {"Mov_PublicMailBox",75}, {"Mov_ShopDisplayCounter",260},
    {"Mov_ShoppingBaskets",85}, {"Mov_SmallPineCabinet",230}, {"Mov_SteelCornerCounter",260},
    {"Mov_SteelCounter",260}, {"Mov_TrailerCounter",260}, {"Mov_TrapezoidShopShelves",310},
    {"Mov_WhiteCornerCounter",260}, {"Mov_WhiteCounter",260}, {"Mov_WhiteFancyDrawers",265},
    {"Mov_WhiteFileCabinet",230}, {"Mov_WoodenCornerCounter",260}, {"Mov_WoodenCounter",260},
})

-- Louças e pias.
addItems("furniture", "DescFurniture", "Móvel posicionável", {
    {"Mov_ChemicalToilet",210}, {"Mov_ChromeSink",220}, {"Mov_DarkIndustrialSink",220},
    {"Mov_FancyHangingSink",270}, {"Mov_FancyToilet",260}, {"Mov_IndustrialSink",220},
    {"Mov_LargeIndustrialSink",300}, {"Mov_LowToilet",210}, {"Mov_ScaleMedical",95},
    {"Mov_Urinal",210}, {"Mov_WallShower",260}, {"Mov_WhiteHangingSink",220},
    {"Mov_WhiteSink",220},
})

-- Contêineres avulsos (barris, tambor, lixeiras) e iluminação externa.
addItems("furniture", "DescFurniture", "Móvel posicionável", {
    {"Mattress",150}, {"MetalDrum",100}, {"Mov_BinRound",80},
    {"Mov_FancyOutdoorLamp",120}, {"Mov_GrayGarbageBin",80}, {"Mov_GreenGarbageBin",80},
    {"Mov_LargeOpenToppedGarbageBin",110}, {"Mov_LightConstruction",150}, {"Mov_LightGreenBarrel",95},
    {"Mov_ModernOutdoorLamp",110}, {"Mov_OrangeBarrel",95}, {"Mov_OvalOutdoorLamp",115},
    {"Mov_PublicGarbageBin",80}, {"Mov_RecycleBin",80}, {"Mov_RoundOutdoorLamp",110},
    {"Mov_WheelieBin",80},
})

-- Acampamento: barracas e sacos de dormir.
addItems("furniture", "DescFurniture", "Móvel posicionável", {
    {"CampingTentKit2",220}, {"HideTent",260}, {"ImprovisedTentKit",180},
    {"SleepingBag_Camo",130}, {"SleepingBag_Cheap_Blue",90}, {"SleepingBag_Hide",140},
    {"SleepingBag_HighQuality_Brown",220}, {"SleepingBag_RedPlaid",130}, {"SleepingBag_Spiffo",110},
    {"TentBrown",240}, {"TentGreen",240},
})

-- Real functional appliances rescued from the 2026-08-21 decorative-junk
-- trim after a follow-up check: unlike Mov_IndustrialDishwasher ("Wash-O-
-- Matic Industrial", the item that started the whole cleanup and correctly
-- stays cut -- its tile has zero function fields), these five DO show up
-- with a real IsoType/ContainerCapacity in the game's own tile data --
-- Mov_BlueComboWasherDryer specifically is what "lava roupas" was asking
-- about: IsoType=IsoCombinationWasherDryer, ContainerCapacity=20, a real
-- working washer/dryer in-game, not a prop.
addItems("furniture", "DescAppliance", "Eletrodoméstico posicionável", {
    {"Mov_BlueComboWasherDryer",420}, {"Mov_BrownDishwasher",380}, {"Mov_DeepFryer",520},
    {"Mov_Espresso",420}, {"Mov_MetalDishwasher",380},
})

-- More rescued items: real containers (coffins, vending machines), real
-- sleep spots (Gurney/Gym Mat/haystacks all carry a BedType field the same
-- way Mov_Cot does), a real heat source (Brazier -- IsoType=IsoFireplace),
-- a real light source (Neon Open Sign -- LightRadius=4), and mannequin-type
-- display objects (Mannequin/Scarecrow/Skeleton Display all share
-- IsoType=IsoMannequin, meaning they can actually hold/display clothing).
addItems("furniture", "DescFurniture", "Móvel posicionável", {
    {"Mov_Brazier",95}, {"Mov_FlatCoffin",220}, {"Mov_Gurney",260},
    {"Mov_GymnMat",95}, {"Mov_HaystackDouble",95}, {"Mov_HaystackSingle",60},
    {"Mov_MannequinFemale",150}, {"Mov_MannequinMale",150}, {"Mov_NeonOpenSign",55},
    {"Mov_Scarecrow",110}, {"Mov_SkeletonDisplay",170}, {"Mov_SnackVendingMachine",400},
    {"Mov_SodaVendingMachine",400}, {"Mov_UprightCoffin",250},
})

-- Alice/Noir-style weapon slings already bundled in Lascivious Scripts as
-- LS_AliceWeaponSling. Sold as equipment, not hidden crafting support parts;
-- the hidden/invisible variants remain out of the store intentionally.
LS.addModdedItems({
    id = "AliceWeaponSling",
}, "clothing", "DescClothing", "Vestuário ou equipamento", {
    {"Base.AliceWeaponSling", 160},
    {"Base.AliceWeaponSlingAlt", 160},
    {"Base.AliceWeaponSlingAlt2", 160},
    {"Base.AliceWeaponSlingBack", 180},
})

-- ===================================================================
-- Modded content: Plysken Solar Revolution (id "PSR", Steam Workshop item
-- 3725311427 -- fork of ImmersiveSolarArrays for Build 42). Off-grid power:
-- solar panels in three mounting styles, a battery bank (the "generator" of
-- this system), five interchangeable battery tiers, and the magazine that
-- unlocks the whole crafting tree. Same shelf as the vanilla Generator*
-- entries above (category="resource", extraCategories={"other"}) per
-- explicit request -- this is the same kind of purchase, just solar instead
-- of gasoline. If PSR is ever removed from the server, every entry below
-- just silently disappears from the client at the next catalog validation
-- (see the big comment above LS.addModdedItems for why that's automatic and
-- safe) -- nothing else in the shop depends on it.
--
-- No isPresent probe: PSR's own Lua never assigns a global table (everything
-- is `local X = require "PSR/Utilities"`), so there's no stable namespace to
-- check from outside the mod. Per the addModdedItems doc comment, that's
-- fine to just omit -- the FindItem() check in validateCatalog() is what
-- actually guarantees safety, not this.
--
-- nameOverride used for every entry PSR itself doesn't name usefully in any
-- language: PowerBank/SolarPanelFlat/SolarPanelWall/SolarPanelMounted/
-- SolarFailsafe have NO entry at all in the mod's own ItemName.json (EN or
-- PTBR) -- getDisplayName() would fall back to the bare script DisplayName
-- field, which for PowerBank is the unspaced literal "PowerBank" in every
-- language. DIYBattery DOES have a PTBR translation, but it's a copy-paste
-- bug in the mod itself: PTBR/ItemName.json gives it the exact same text as
-- ImprovisedBattery ("Bateria Improvisada"/"Bateria improvisada", differing
-- only by capitalization) even though they're different tiers (200Ah/slower
-- degrade vs 100Ah/faster degrade) -- confirmed against the mod's own
-- (correct, distinct) PT/EN files. Every other entry below already has a
-- proper, distinct PTBR name in the mod itself and is left alone.
LS.addModdedItems({
    id = "PlyskenSolarRevolution",
}, "resource", "DescSolarEquipment", "Equipamento de energia solar", {
    {"PSR.SolarPanel", 900, nil, nil, "DescPSRSolarPanel",
        "Painel solar ainda nao montado.",
        extraCategories={"other"}},
    {"PSR.PSRInverter", 550, nil, nil, "DescPSRInverter",
        "Converte energia das baterias para a casa.",
        extraCategories={"other"}},
    {"PSR.WiredCarBattery", 380, nil, nil, "DescPSRWiredCarBattery",
        "Bateria de carro adaptada, 50Ah. Degrada rapido.",
        extraCategories={"other"}},
    {"PSR.ImprovisedBattery", 650, nil, nil, "DescPSRImprovisedBattery",
        "Bateria improvisada, 100Ah. Degrada rapido.",
        extraCategories={"other"}},
    {"PSR.DIYBattery", 1050, nil, nil, "DescPSRDIYBattery",
        "Bateria artesanal, 200Ah. Degrada rapido.",
        nameOverrideKey="NamePSRDIYBattery", nameOverride="Bateria Artesanal 200Ah", extraCategories={"other"}},
    {"PSR.DeepCycleBattery", 1400, nil, nil, "DescPSRDeepCycleBattery",
        "Ciclo profundo, 200Ah. Degrada devagar.",
        extraCategories={"other"}},
    {"PSR.SuperBattery", 2400, nil, nil, "DescPSRSuperBattery",
        "Ciclo profundo, 400Ah. Degrada devagar.",
        extraCategories={"other"}},
    {"PSR.PowerBank", 2800, nil, nil, "DescPSRPowerBank",
        "Armazena energia solar e alimenta a casa.",
        nameOverrideKey="NamePSRPowerBank", nameOverride="Banco de Baterias Solar", extraCategories={"other"}},
    {"PSR.SolarPanelFlat", 1150, nil, nil, "DescPSRSolarPanelFlat",
        "Painel solar pronto, instalacao em telhado.",
        nameOverrideKey="NamePSRSolarPanelFlat", nameOverride="Painel Solar (Telhado)", extraCategories={"other"}},
    {"PSR.SolarPanelWall", 1150, nil, nil, "DescPSRSolarPanelWall",
        "Painel solar pronto, instalacao em parede.",
        nameOverrideKey="NamePSRSolarPanelWall", nameOverride="Painel Solar (Parede)", extraCategories={"other"}},
    {"PSR.SolarPanelMounted", 1150, nil, nil, "DescPSRSolarPanelMounted",
        "Painel solar pronto, instalacao no chao.",
        nameOverrideKey="NamePSRSolarPanelMounted", nameOverride="Painel Solar (Chao)", extraCategories={"other"}},
    {"PSR.SolarFailsafe", 420, nil, nil, "DescPSRSolarFailsafe",
        "Protege o banco de baterias contra sobrecarga.",
        nameOverrideKey="NamePSRSolarFailsafe", nameOverride="Mecanismo de Seguranca Solar", extraCategories={"other"}},
})
LS.addModdedItems({
    id = "PlyskenSolarRevolution",
}, "other", "DescRecipeMagazine", "Revista de receitas", {
    {"PSR.PSRMag1", 580, nil, nil, "DescPSRMag1",
        "Ensina as receitas do sistema de energia solar."},
})

-- ===================================================================
-- Modded content: Guns of Marz (GoM, id "GunsOfMarz", requires the Gunworks
-- framework "SWMG" -- Steam Workshop items 3722134990 and 3722064198). Adds
-- ~300 sellable items: 70 firearms, 5 melee/bayonets, 3 grenades, loose
-- rounds, ammo boxes/cartons/crates, per-weapon magazines, ~70 real
-- attachments and a repair pack.
--
-- GoM is treated as INCOMPATIBLE with vanilla firearms on this server --
-- explicit server design decision, not something GoM enforces itself
-- (confirmed by reading its own Distribution/ItemInsertion.lua: it only ever
-- ADDS its own spawners to vanilla loot tables, never edits/removes vanilla
-- entries). GoMCompat.lua (shared/) is the single detection point both this
-- catalog and HardcoreKits_Validation.lua rely on. When GoM is active,
-- LasciviousShop_Server.lua's validateCatalog() hides every vanilla-sourced
-- "firearm"/"ammo" product (sourceMod == nil) so only the GoM entries below
-- remain purchasable -- see the comment there for exactly how.
--
-- isPresent on the firearm block only (the rest share modInfo.id "GunsOfMarz"
-- without repeating the probe) is purely diagnostic, same as every other
-- addModdedItems call -- never what actually hides/shows an item, that's
-- validateCatalog()'s unconditional FindItem() check plus the vanilla-hiding
-- rule above.
--
-- Pricing: generated from each weapon's own MinDamage/MaxDamage/MaxAmmo
-- (scaled within its weapon-family tier, e.g. pistols 130-260, LMGs/launchers
-- 550-750), magazines scaled by capacity, ammo by a caliber tier table,
-- attachments by subcategory. Not hand-tuned per item -- 300 items is well
-- past the point where that's practical -- but every number was cross-checked
-- against the real script fields, and the whole set is deliberately priced
-- above the vanilla firearm/ammo scale it replaces (see LS.PRODUCTS' vanilla
-- "firearm"/"ammo" blocks above for comparison), matching how the PSR solar
-- batch was priced ("balanceado, não barato").
--
-- Excluded on purpose (confirmed by reading every item's own script fields,
-- not guessed): the 42 "*_Spawner" items (zombie-loadout spawners, never
-- player-facing), 4 "FakeItem*"/"explosion_0" junk placeholders
-- (DisplayCategory=Junk), all 25 "ammo_casings" (spent-casing reloading
-- components, not standalone ammo), the two "40mm_*_Explosion" items
-- (ambiguous internal detonation objects, not the real 40mm ammo -- that's
-- in ammo_boxes/ammo_rounds under "40mm_*"), and 57 attachment items across
-- attachments/details.txt, integrated.txt, animated.txt and bayonets.txt --
-- every single one of those four files is MountOn=MarzGuns.FakeItem, i.e.
-- internal per-weapon animation-state components (bipod/stock Folded vs
-- Deployed, bolt/slide/pump Lock vs Fired, magazine-visible-round markers),
-- confirmed by cross-checking MountOn across every attachment file: every
-- REAL attachment kept below lists an actual weapon compatibility list
-- instead of the FakeItem placeholder.
LS.addModdedItems({
    id = "GunsOfMarz",
    isPresent = function() return GoMCompat ~= nil and GoMCompat.isActive() end,
}, "firearm", "DescFirearm", "Arma de fogo", {
    {"MarzGuns.AA12", 380, nil, nil, nil, nil, nameOverrideKey="NameGoMAA12"},
    {"MarzGuns.AK47", 480, nil, nil, nil, nil, nameOverrideKey="NameGoMAK47"},
    {"MarzGuns.AK74", 520, nil, nil, nil, nil, nameOverrideKey="NameGoMAK74"},
    {"MarzGuns.AKS74U", 410, nil, nil, nil, nil, nameOverrideKey="NameGoMAKS74U"},
    {"MarzGuns.AR15", 410, nil, nil, nil, nil, nameOverrideKey="NameGoMAR15"},
    {"MarzGuns.ASVAL", 340, nil, nil, nil, nil, nameOverrideKey="NameGoMASVAL"},
    {"MarzGuns.BAR", 600, nil, nil, nil, nil, nameOverrideKey="NameGoMBAR"},
    {"MarzGuns.BENELLI_M4", 360, nil, nil, nil, nil, nameOverrideKey="NameGoMBENELLI_M4"},
    {"MarzGuns.CAMP_CARBINE", 300, nil, nil, nil, nil, nameOverrideKey="NameGoMCAMP_CARBINE"},
    {"MarzGuns.CAR15", 380, nil, nil, nil, nil, nameOverrideKey="NameGoMCAR15"},
    {"MarzGuns.COLT_SINGLE", 170, nil, nil, nil, nil, nameOverrideKey="NameGoMCOLT_SINGLE"},
    {"MarzGuns.DEAGLE", 260, nil, nil, nil, nil, nameOverrideKey="NameGoMDEAGLE"},
    {"MarzGuns.DETECTIVE_38", 130, nil, nil, nil, nil, nameOverrideKey="NameGoMDETECTIVE_38"},
    {"MarzGuns.DOUBLEBARREL", 240, nil, nil, nil, nil, nameOverrideKey="NameGoMDOUBLEBARREL"},
    {"MarzGuns.FAL", 380, nil, nil, nil, nil, nameOverrideKey="NameGoMFAL"},
    {"MarzGuns.FAMAS", 450, nil, nil, nil, nil, nameOverrideKey="NameGoMFAMAS"},
    {"MarzGuns.FNC", 450, nil, nil, nil, nil, nameOverrideKey="NameGoMFNC"},
    {"MarzGuns.G3", 380, nil, nil, nil, nil, nameOverrideKey="NameGoMG3"},
    {"MarzGuns.G36", 340, nil, nil, nil, nil, nameOverrideKey="NameGoMG36"},
    {"MarzGuns.G36C", 340, nil, nil, nil, nil, nameOverrideKey="NameGoMG36C"},
    {"MarzGuns.HIPOWER", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMHIPOWER"},
    {"MarzGuns.M14", 460, nil, nil, nil, nil, nameOverrideKey="NameGoMM14"},
    {"MarzGuns.M16A1", 480, nil, nil, nil, nil, nameOverrideKey="NameGoMM16A1"},
    {"MarzGuns.M16A2", 480, nil, nil, nil, nil, nameOverrideKey="NameGoMM16A2"},
    {"MarzGuns.M16A2_M203", 480, nil, nil, nil, nil, nameOverrideKey="NameGoMM16A2_M203"},
    {"MarzGuns.M16A3", 480, nil, nil, nil, nil, nameOverrideKey="NameGoMM16A3"},
    {"MarzGuns.M1895", 320, nil, nil, nil, nil, nameOverrideKey="NameGoMM1895"},
    {"MarzGuns.M1903", 480, nil, nil, nil, nil, nameOverrideKey="NameGoMM1903"},
    {"MarzGuns.M1911", 170, nil, nil, nil, nil, nameOverrideKey="NameGoMM1911"},
    {"MarzGuns.M1_GARAND", 520, nil, nil, nil, nil, nameOverrideKey="NameGoMM1_GARAND"},
    {"MarzGuns.M203_Weapon", 620, nil, nil, nil, nil, nameOverrideKey="NameGoMM203_Weapon"},
    {"MarzGuns.M24", 430, nil, nil, nil, nil, nameOverrideKey="NameGoMM24"},
    {"MarzGuns.M4A1", 340, nil, nil, nil, nil, nameOverrideKey="NameGoMM4A1"},
    {"MarzGuns.M60", 750, nil, nil, nil, nil, nameOverrideKey="NameGoMM60"},
    {"MarzGuns.M79", 620, nil, nil, nil, nil, nameOverrideKey="NameGoMM79"},
    {"MarzGuns.M92FS", 150, nil, nil, nil, nil, nameOverrideKey="NameGoMM92FS"},
    {"MarzGuns.M93R", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMM93R"},
    {"MarzGuns.MAC10", 220, nil, nil, nil, nil, nameOverrideKey="NameGoMMAC10"},
    {"MarzGuns.MASTERKEY_Weapon", 620, nil, nil, nil, nil, nameOverrideKey="NameGoMMASTERKEY_Weapon"},
    {"MarzGuns.MINI_14", 380, nil, nil, nil, nil, nameOverrideKey="NameGoMMINI_14"},
    {"MarzGuns.MODEL_70", 320, nil, nil, nil, nil, nameOverrideKey="NameGoMMODEL_70"},
    {"MarzGuns.MOSIN", 480, nil, nil, nil, nil, nameOverrideKey="NameGoMMOSIN"},
    {"MarzGuns.MOSSBERG_590", 310, nil, nil, nil, nil, nameOverrideKey="NameGoMMOSSBERG_590"},
    {"MarzGuns.MP412", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMMP412"},
    {"MarzGuns.MP5", 320, nil, nil, nil, nil, nameOverrideKey="NameGoMMP5"},
    {"MarzGuns.MP5A2", 320, nil, nil, nil, nil, nameOverrideKey="NameGoMMP5A2"},
    {"MarzGuns.MP5K", 200, nil, nil, nil, nil, nameOverrideKey="NameGoMMP5K"},
    {"MarzGuns.MP5SD", 260, nil, nil, nil, nil, nameOverrideKey="NameGoMMP5SD"},
    {"MarzGuns.P226", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMP226"},
    {"MarzGuns.PSG1", 440, nil, nil, nil, nil, nameOverrideKey="NameGoMPSG1"},
    {"MarzGuns.PYTHON", 220, nil, nil, nil, nil, nameOverrideKey="NameGoMPYTHON"},
    {"MarzGuns.REMINGTON_700", 390, nil, nil, nil, nil, nameOverrideKey="NameGoMREMINGTON_700"},
    {"MarzGuns.REMINGTON_870", 310, nil, nil, nil, nil, nameOverrideKey="NameGoMREMINGTON_870"},
    {"MarzGuns.RHINO", 190, nil, nil, nil, nil, nameOverrideKey="NameGoMRHINO"},
    {"MarzGuns.SKS", 440, nil, nil, nil, nil, nameOverrideKey="NameGoMSKS"},
    {"MarzGuns.SPAS12", 360, nil, nil, nil, nil, nameOverrideKey="NameGoMSPAS12"},
    {"MarzGuns.STEVENS_555", 240, nil, nil, nil, nil, nameOverrideKey="NameGoMSTEVENS_555"},
    {"MarzGuns.SVD", 440, nil, nil, nil, nil, nameOverrideKey="NameGoMSVD"},
    {"MarzGuns.SW629", 240, nil, nil, nil, nil, nameOverrideKey="NameGoMSW629"},
    {"MarzGuns.TEC9", 200, nil, nil, nil, nil, nameOverrideKey="NameGoMTEC9"},
    {"MarzGuns.THOMPSON", 320, nil, nil, nil, nil, nameOverrideKey="NameGoMTHOMPSON"},
    {"MarzGuns.TOZ34", 240, nil, nil, nil, nil, nameOverrideKey="NameGoMTOZ34"},
    {"MarzGuns.TRENCHGUN", 310, nil, nil, nil, nil, nameOverrideKey="NameGoMTRENCHGUN"},
    {"MarzGuns.USP", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMUSP"},
    {"MarzGuns.VP70M", 260, nil, nil, nil, nil, nameOverrideKey="NameGoMVP70M"},
    {"MarzGuns.W1873", 200, nil, nil, nil, nil, nameOverrideKey="NameGoMW1873"},
    {"MarzGuns.W1873_CARBINE", 200, nil, nil, nil, nil, nameOverrideKey="NameGoMW1873_CARBINE"},
    {"MarzGuns.W1887", 250, nil, nil, nil, nil, nameOverrideKey="NameGoMW1887"},
    {"MarzGuns.W1894", 210, nil, nil, nil, nil, nameOverrideKey="NameGoMW1894"},
    {"MarzGuns.XM177", 380, nil, nil, nil, nil, nameOverrideKey="NameGoMXM177"},
})

LS.addModdedItems({ id = "GunsOfMarz" }, "melee", "DescMelee", "Arma corpo a corpo", {
    {"MarzGuns.Attack_Bayonet", 170, nil, nil, nil, nil, nameOverrideKey="NameGoMAttack_Bayonet"},
    {"MarzGuns.Elvorenstein_Tacticool_Knife", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMElvorenstein_Tacticool_Knife"},
    {"MarzGuns.K98_BAYONET", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMK98_BAYONET"},
    {"MarzGuns.M5_BAYONET", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMM5_BAYONET"},
    {"MarzGuns.M9_BAYONET", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMM9_BAYONET"},
})

LS.addModdedItems({ id = "GunsOfMarz" }, "other", "DescExplosive", "Explosivo ou dispositivo", {
    {"MarzGuns.M14_Incendiary", 200, nil, nil, nil, nil, nameOverrideKey="NameGoMM14_Incendiary"},
    {"MarzGuns.M18", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMM18"},
    {"MarzGuns.M67", 220, nil, nil, nil, nil, nameOverrideKey="NameGoMM67"},
})

LS.addModdedItems({ id = "GunsOfMarz" }, "ammo", "DescAmmoRound", "Munição avulsa", {
    {"MarzGuns.12Gauge_Shell_Buckshot", 10, nil, nil, nil, nil, nameOverrideKey="NameGoM12Gauge_Shell_Buckshot"},
    {"MarzGuns.12Gauge_Shell_Slug", 10, nil, nil, nil, nil, nameOverrideKey="NameGoM12Gauge_Shell_Slug"},
    {"MarzGuns.223_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM223_Bullet"},
    {"MarzGuns.3006_Bullet", 10, nil, nil, nil, nil, nameOverrideKey="NameGoM3006_Bullet"},
    {"MarzGuns.3030_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM3030_Bullet"},
    {"MarzGuns.308_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM308_Bullet"},
    {"MarzGuns.357_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM357_Bullet"},
    {"MarzGuns.38_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM38_Bullet"},
    {"MarzGuns.40mm_Round_Buckshot", 15, nil, nil, nil, nil, nameOverrideKey="NameGoM40mm_Round_Buckshot"},
    {"MarzGuns.40mm_Round_HE", 15, nil, nil, nil, nil, nameOverrideKey="NameGoM40mm_Round_HE"},
    {"MarzGuns.40mm_Round_Incendiary", 15, nil, nil, nil, nil, nameOverrideKey="NameGoM40mm_Round_Incendiary"},
    {"MarzGuns.44_Bullet", 10, nil, nil, nil, nil, nameOverrideKey="NameGoM44_Bullet"},
    {"MarzGuns.4570_Bullet", 10, nil, nil, nil, nil, nameOverrideKey="NameGoM4570_Bullet"},
    {"MarzGuns.45_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM45_Bullet"},
    {"MarzGuns.50_Bullet", 15, nil, nil, nil, nil, nameOverrideKey="NameGoM50_Bullet"},
    {"MarzGuns.545x39_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM545x39_Bullet"},
    {"MarzGuns.556x45_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Bullet"},
    {"MarzGuns.556x45_Bullet_ArmorPiercing", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Bullet_ArmorPiercing"},
    {"MarzGuns.556x45_Bullet_HollowPoint", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Bullet_HollowPoint"},
    {"MarzGuns.556x45_Bullet_Overpressured", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Bullet_Overpressured"},
    {"MarzGuns.556x45_Bullet_Subsonic", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Bullet_Subsonic"},
    {"MarzGuns.762x39_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM762x39_Bullet"},
    {"MarzGuns.762x51_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM762x51_Bullet"},
    {"MarzGuns.762x54_Bullet", 10, nil, nil, nil, nil, nameOverrideKey="NameGoM762x54_Bullet"},
    {"MarzGuns.9x19_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19_Bullet"},
    {"MarzGuns.9x39_Bullet", 5, nil, nil, nil, nil, nameOverrideKey="NameGoM9x39_Bullet"},
})

LS.addModdedItems({ id = "GunsOfMarz" }, "ammo", "DescAmmoBox", "Caixa de munição", {
    {"MarzGuns.12Gauge_Box_Buckshot", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM12Gauge_Box_Buckshot"},
    {"MarzGuns.12Gauge_Box_Slug", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM12Gauge_Box_Slug"},
    {"MarzGuns.12Gauge_Carton_Buckshot", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM12Gauge_Carton_Buckshot"},
    {"MarzGuns.12Gauge_Carton_Slug", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM12Gauge_Carton_Slug"},
    {"MarzGuns.12Gauge_Crate_Buckshot", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM12Gauge_Crate_Buckshot"},
    {"MarzGuns.12Gauge_Crate_Slug", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM12Gauge_Crate_Slug"},
    {"MarzGuns.223_Box", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM223_Box"},
    {"MarzGuns.223_Carton", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM223_Carton"},
    {"MarzGuns.223_Crate", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM223_Crate"},
    {"MarzGuns.3006_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM3006_Box"},
    {"MarzGuns.3006_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM3006_Carton"},
    {"MarzGuns.3006_Crate", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM3006_Crate"},
    {"MarzGuns.3030_Box", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM3030_Box"},
    {"MarzGuns.3030_Carton", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM3030_Carton"},
    {"MarzGuns.3030_Crate", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM3030_Crate"},
    {"MarzGuns.308_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM308_Box"},
    {"MarzGuns.308_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM308_Carton"},
    {"MarzGuns.308_Crate", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM308_Crate"},
    {"MarzGuns.357_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM357_Box"},
    {"MarzGuns.357_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM357_Carton"},
    {"MarzGuns.357_Crate", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM357_Crate"},
    {"MarzGuns.38_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM38_Box"},
    {"MarzGuns.38_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM38_Carton"},
    {"MarzGuns.38_Crate", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM38_Crate"},
    {"MarzGuns.40mm_Box_Buckshot", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM40mm_Box_Buckshot"},
    {"MarzGuns.40mm_Box_HE", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM40mm_Box_HE"},
    {"MarzGuns.40mm_Box_Incendiary", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM40mm_Box_Incendiary"},
    {"MarzGuns.44_Box", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM44_Box"},
    {"MarzGuns.44_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM44_Carton"},
    {"MarzGuns.44_Crate", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM44_Crate"},
    {"MarzGuns.4570_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM4570_Box"},
    {"MarzGuns.4570_Carton", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM4570_Carton"},
    {"MarzGuns.4570_Crate", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM4570_Crate"},
    {"MarzGuns.45_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM45_Box"},
    {"MarzGuns.45_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM45_Carton"},
    {"MarzGuns.45_Crate", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM45_Crate"},
    {"MarzGuns.50_Box", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM50_Box"},
    {"MarzGuns.50_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM50_Carton"},
    {"MarzGuns.50_Crate", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM50_Crate"},
    {"MarzGuns.545x39_Box", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM545x39_Box"},
    {"MarzGuns.545x39_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM545x39_Carton"},
    {"MarzGuns.545x39_Crate", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM545x39_Crate"},
    {"MarzGuns.556x45_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Box"},
    {"MarzGuns.556x45_Box_ArmorPiercing", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Box_ArmorPiercing"},
    {"MarzGuns.556x45_Box_HollowPoint", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Box_HollowPoint"},
    {"MarzGuns.556x45_Box_Overpressured", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Box_Overpressured"},
    {"MarzGuns.556x45_Box_Subsonic", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Box_Subsonic"},
    {"MarzGuns.556x45_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Carton"},
    {"MarzGuns.556x45_Carton_ArmorPiercing", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Carton_ArmorPiercing"},
    {"MarzGuns.556x45_Carton_HollowPoint", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Carton_HollowPoint"},
    {"MarzGuns.556x45_Carton_Overpressured", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Carton_Overpressured"},
    {"MarzGuns.556x45_Carton_Subsonic", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Carton_Subsonic"},
    {"MarzGuns.556x45_Crate", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Crate"},
    {"MarzGuns.556x45_Crate_ArmorPiercing", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Crate_ArmorPiercing"},
    {"MarzGuns.556x45_Crate_HollowPoint", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Crate_HollowPoint"},
    {"MarzGuns.556x45_Crate_Overpressured", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Crate_Overpressured"},
    {"MarzGuns.556x45_Crate_Subsonic", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45_Crate_Subsonic"},
    {"MarzGuns.762x39_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM762x39_Box"},
    {"MarzGuns.762x39_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM762x39_Carton"},
    {"MarzGuns.762x39_Crate", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM762x39_Crate"},
    {"MarzGuns.762x51_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM762x51_Box"},
    {"MarzGuns.762x51_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM762x51_Carton"},
    {"MarzGuns.762x51_Crate", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM762x51_Crate"},
    {"MarzGuns.762x54_Box", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM762x54_Box"},
    {"MarzGuns.762x54_Carton", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM762x54_Carton"},
    {"MarzGuns.762x54_Crate", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM762x54_Crate"},
    {"MarzGuns.9x19_Box", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19_Box"},
    {"MarzGuns.9x19_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19_Carton"},
    {"MarzGuns.9x19_Crate", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19_Crate"},
    {"MarzGuns.9x39_Box", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM9x39_Box"},
    {"MarzGuns.9x39_Carton", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM9x39_Carton"},
    {"MarzGuns.9x39_Crate", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM9x39_Crate"},
})

LS.addModdedItems({ id = "GunsOfMarz" }, "ammo", "DescMagazine", "Carregador vazio", {
    {"MarzGuns.12GMagazine20_AA12", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM12GMagazine20_AA12"},
    {"MarzGuns.12GMagazine8_AA12", 40, nil, nil, nil, nil, nameOverrideKey="NameGoM12GMagazine8_AA12"},
    {"MarzGuns.223Magazine10_Mini14", 40, nil, nil, nil, nil, nameOverrideKey="NameGoM223Magazine10_Mini14"},
    {"MarzGuns.223Magazine20_Mini14", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM223Magazine20_Mini14"},
    {"MarzGuns.223Magazine30_Mini14", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM223Magazine30_Mini14"},
    {"MarzGuns.3006Clip8", 40, nil, nil, nil, nil, nameOverrideKey="NameGoM3006Clip8"},
    {"MarzGuns.3006Magazine20_BAR", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM3006Magazine20_BAR"},
    {"MarzGuns.38357SpeedLoader6", 35, nil, nil, nil, nil, nameOverrideKey="NameGoM38357SpeedLoader6"},
    {"MarzGuns.45Magazine100_THOMPSON", 180, nil, nil, nil, nil, nameOverrideKey="NameGoM45Magazine100_THOMPSON"},
    {"MarzGuns.45Magazine12_USP", 40, nil, nil, nil, nil, nameOverrideKey="NameGoM45Magazine12_USP"},
    {"MarzGuns.45Magazine20_THOMPSON", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM45Magazine20_THOMPSON"},
    {"MarzGuns.45Magazine20_USP", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM45Magazine20_USP"},
    {"MarzGuns.45Magazine30_MAC10", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM45Magazine30_MAC10"},
    {"MarzGuns.45Magazine30_THOMPSON", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM45Magazine30_THOMPSON"},
    {"MarzGuns.45Magazine40_MAC10", 80, nil, nil, nil, nil, nameOverrideKey="NameGoM45Magazine40_MAC10"},
    {"MarzGuns.45Magazine7_M1911", 35, nil, nil, nil, nil, nameOverrideKey="NameGoM45Magazine7_M1911"},
    {"MarzGuns.50Magazine12_DEAGLE", 40, nil, nil, nil, nil, nameOverrideKey="NameGoM50Magazine12_DEAGLE"},
    {"MarzGuns.50Magazine8_DEAGLE", 40, nil, nil, nil, nil, nameOverrideKey="NameGoM50Magazine8_DEAGLE"},
    {"MarzGuns.545x39Magazine100_Drum", 180, nil, nil, nil, nil, nameOverrideKey="NameGoM545x39Magazine100_Drum"},
    {"MarzGuns.545x39Magazine30_Bakelite", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM545x39Magazine30_Bakelite"},
    {"MarzGuns.545x39Magazine45_Bakelite", 90, nil, nil, nil, nil, nameOverrideKey="NameGoM545x39Magazine45_Bakelite"},
    {"MarzGuns.556x45Magazine100_STANAG", 180, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45Magazine100_STANAG"},
    {"MarzGuns.556x45Magazine150_STANAG", 180, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45Magazine150_STANAG"},
    {"MarzGuns.556x45Magazine20_STANAG", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45Magazine20_STANAG"},
    {"MarzGuns.556x45Magazine25_STANAG", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45Magazine25_STANAG"},
    {"MarzGuns.556x45Magazine30_G36", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45Magazine30_G36"},
    {"MarzGuns.556x45Magazine30_STANAG", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45Magazine30_STANAG"},
    {"MarzGuns.556x45Magazine50_STANAG", 100, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45Magazine50_STANAG"},
    {"MarzGuns.556x45Magazine60_STANAG", 130, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45Magazine60_STANAG"},
    {"MarzGuns.556x45Magazine75_STANAG", 150, nil, nil, nil, nil, nameOverrideKey="NameGoM556x45Magazine75_STANAG"},
    {"MarzGuns.762x39Magazine30", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM762x39Magazine30"},
    {"MarzGuns.762x39Magazine75", 150, nil, nil, nil, nil, nameOverrideKey="NameGoM762x39Magazine75"},
    {"MarzGuns.762x51Box100_M60", 180, nil, nil, nil, nil, nameOverrideKey="NameGoM762x51Box100_M60"},
    {"MarzGuns.762x51Magazine20_FAL", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM762x51Magazine20_FAL"},
    {"MarzGuns.762x51Magazine20_G3", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM762x51Magazine20_G3"},
    {"MarzGuns.762x51Magazine20_M14", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM762x51Magazine20_M14"},
    {"MarzGuns.762x51Magazine5_PSG1", 35, nil, nil, nil, nil, nameOverrideKey="NameGoM762x51Magazine5_PSG1"},
    {"MarzGuns.762x54Magazine10_SVD", 40, nil, nil, nil, nil, nameOverrideKey="NameGoM762x54Magazine10_SVD"},
    {"MarzGuns.762x54StripperClip5_MOSIN", 35, nil, nil, nil, nil, nameOverrideKey="NameGoM762x54StripperClip5_MOSIN"},
    {"MarzGuns.9x19Magazine100_MP5", 180, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine100_MP5"},
    {"MarzGuns.9x19Magazine10_P226", 40, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine10_P226"},
    {"MarzGuns.9x19Magazine13_HIPOWER", 45, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine13_HIPOWER"},
    {"MarzGuns.9x19Magazine15_M92FS", 45, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine15_M92FS"},
    {"MarzGuns.9x19Magazine18_M93R", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine18_M93R"},
    {"MarzGuns.9x19Magazine18_VP70M", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine18_VP70M"},
    {"MarzGuns.9x19Magazine20_MP5", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine20_MP5"},
    {"MarzGuns.9x19Magazine20_TEC9", 50, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine20_TEC9"},
    {"MarzGuns.9x19Magazine25_MP5", 60, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine25_MP5"},
    {"MarzGuns.9x19Magazine30_M92FS", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine30_M92FS"},
    {"MarzGuns.9x19Magazine30_MP5", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine30_MP5"},
    {"MarzGuns.9x19Magazine30_VP70M", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine30_VP70M"},
    {"MarzGuns.9x19Magazine50_M92FS", 100, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine50_M92FS"},
    {"MarzGuns.9x19Magazine60_M93R", 130, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine60_M93R"},
    {"MarzGuns.9x19Magazine60_MP5", 130, nil, nil, nil, nil, nameOverrideKey="NameGoM9x19Magazine60_MP5"},
    {"MarzGuns.9x39Magazine30", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM9x39Magazine30"},
})

LS.addModdedItems({ id = "GunsOfMarz" }, "ammo", "DescWeaponPart", "Acessório para arma", {
    {"MarzGuns.45_Muzzle_Mount_Device", 70, nil, nil, nil, nil, nameOverrideKey="NameGoM45_Muzzle_Mount_Device"},
    {"MarzGuns.AK_Mount", 60, nil, nil, nil, nil, nameOverrideKey="NameGoMAK_Mount"},
    {"MarzGuns.AK_Muzzle_Mount_Device", 60, nil, nil, nil, nil, nameOverrideKey="NameGoMAK_Muzzle_Mount_Device"},
    {"MarzGuns.AR_Muzzle_Mount_Device", 90, nil, nil, nil, nil, nameOverrideKey="NameGoMAR_Muzzle_Mount_Device"},
    {"MarzGuns.AimRight_Laser", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMAimRight_Laser"},
    {"MarzGuns.Aimpoint_Sight", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMAimpoint_Sight"},
    {"MarzGuns.Beretta_Mount", 45, nil, nil, nil, nil, nameOverrideKey="NameGoMBeretta_Mount"},
    {"MarzGuns.Beretta_Stock_Deployed", 120, nil, nil, nil, nil, nameOverrideKey="NameGoMBeretta_Stock_Deployed"},
    {"MarzGuns.Beretta_Stock_Folded", 150, nil, nil, nil, nil, nameOverrideKey="NameGoMBeretta_Stock_Folded"},
    {"MarzGuns.Bipod_Deployed", 120, nil, nil, nil, nil, nameOverrideKey="NameGoMBipod_Deployed"},
    {"MarzGuns.Bipod_Folded", 80, nil, nil, nil, nil, nameOverrideKey="NameGoMBipod_Folded"},
    {"MarzGuns.BrightPoint-5_Light", 130, nil, nil, nil, nil, nameOverrideKey="NameGoMBrightPoint-5_Light"},
    {"MarzGuns.Colt_Mount", 60, nil, nil, nil, nil, nameOverrideKey="NameGoMColt_Mount"},
    {"MarzGuns.DOUBLEBARREL_Barrel_Close", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMDOUBLEBARREL_Barrel_Close"},
    {"MarzGuns.DOUBLEBARREL_Barrel_Open", 130, nil, nil, nil, nil, nameOverrideKey="NameGoMDOUBLEBARREL_Barrel_Open"},
    {"MarzGuns.DOUBLEBARREL_Barrel_Sawnoff_Close", 100, nil, nil, nil, nil, nameOverrideKey="NameGoMDOUBLEBARREL_Barrel_Sawnoff_Close"},
    {"MarzGuns.DOUBLEBARREL_Barrel_Sawnoff_Open", 150, nil, nil, nil, nil, nameOverrideKey="NameGoMDOUBLEBARREL_Barrel_Sawnoff_Open"},
    {"MarzGuns.EXPS1_Sight", 180, nil, nil, nil, nil, nameOverrideKey="NameGoMEXPS1_Sight"},
    {"MarzGuns.EXPS3_Sight", 190, nil, nil, nil, nil, nameOverrideKey="NameGoMEXPS3_Sight"},
    {"MarzGuns.ElcanX2_Scope", 170, nil, nil, nil, nil, nameOverrideKey="NameGoMElcanX2_Scope"},
    {"MarzGuns.Heavy_Pistol_Rail", 70, nil, nil, nil, nil, nameOverrideKey="NameGoMHeavy_Pistol_Rail"},
    {"MarzGuns.JS14_Sight", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMJS14_Sight"},
    {"MarzGuns.Kobra_Sight", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMKobra_Sight"},
    {"MarzGuns.LP_Light", 110, nil, nil, nil, nil, nameOverrideKey="NameGoMLP_Light"},
    {"MarzGuns.LR10X_Scope", 170, nil, nil, nil, nil, nameOverrideKey="NameGoMLR10X_Scope"},
    {"MarzGuns.LR2_Compensator", 70, nil, nil, nil, nil, nameOverrideKey="NameGoMLR2_Compensator"},
    {"MarzGuns.LR4X_Scope", 180, nil, nil, nil, nil, nameOverrideKey="NameGoMLR4X_Scope"},
    {"MarzGuns.LRX-7_Laser", 130, nil, nil, nil, nil, nameOverrideKey="NameGoMLRX-7_Laser"},
    {"MarzGuns.LRX12X_Scope", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMLRX12X_Scope"},
    {"MarzGuns.LX_Flashhider", 70, nil, nil, nil, nil, nameOverrideKey="NameGoMLX_Flashhider"},
    {"MarzGuns.MK2_Foregrip", 80, nil, nil, nil, nil, nameOverrideKey="NameGoMMK2_Foregrip"},
    {"MarzGuns.MKC_Foregrip", 60, nil, nil, nil, nil, nameOverrideKey="NameGoMMKC_Foregrip"},
    {"MarzGuns.MKI_Suppressor", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMMKI_Suppressor"},
    {"MarzGuns.Model_70_Sling", 180, nil, nil, nil, nil, nameOverrideKey="NameGoMModel_70_Sling"},
    {"MarzGuns.NDR_Suppressor", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMNDR_Suppressor"},
    {"MarzGuns.OKP3_Sight", 150, nil, nil, nil, nil, nameOverrideKey="NameGoMOKP3_Sight"},
    {"MarzGuns.P45_Suppressor", 230, nil, nil, nil, nil, nameOverrideKey="NameGoMP45_Suppressor"},
    {"MarzGuns.PBS-1_Suppressor", 200, nil, nil, nil, nil, nameOverrideKey="NameGoMPBS-1_Suppressor"},
    {"MarzGuns.PJ-3_Laser", 120, nil, nil, nil, nil, nameOverrideKey="NameGoMPJ-3_Laser"},
    {"MarzGuns.PL4_Sight", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMPL4_Sight"},
    {"MarzGuns.PM2_Sight", 130, nil, nil, nil, nil, nameOverrideKey="NameGoMPM2_Sight"},
    {"MarzGuns.PRL1_Scope", 120, nil, nil, nil, nil, nameOverrideKey="NameGoMPRL1_Scope"},
    {"MarzGuns.PS1_Sight", 170, nil, nil, nil, nil, nameOverrideKey="NameGoMPS1_Sight"},
    {"MarzGuns.PSO1_Scope", 200, nil, nil, nil, nil, nameOverrideKey="NameGoMPSO1_Scope"},
    {"MarzGuns.PX1_Laser", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMPX1_Laser"},
    {"MarzGuns.Picatinny_Rail", 70, nil, nil, nil, nil, nameOverrideKey="NameGoMPicatinny_Rail"},
    {"MarzGuns.Picatinny_Rail_Down", 60, nil, nil, nil, nil, nameOverrideKey="NameGoMPicatinny_Rail_Down"},
    {"MarzGuns.Picatinny_Rail_Left", 70, nil, nil, nil, nil, nameOverrideKey="NameGoMPicatinny_Rail_Left"},
    {"MarzGuns.Picatinny_Rail_Right", 70, nil, nil, nil, nil, nameOverrideKey="NameGoMPicatinny_Rail_Right"},
    {"MarzGuns.Picatinny_Rail_Up", 70, nil, nil, nil, nil, nameOverrideKey="NameGoMPicatinny_Rail_Up"},
    {"MarzGuns.Pistol_Muzzle_Mount_Device", 70, nil, nil, nil, nil, nameOverrideKey="NameGoMPistol_Muzzle_Mount_Device"},
    {"MarzGuns.ReflexS2_Sight", 190, nil, nil, nil, nil, nameOverrideKey="NameGoMReflexS2_Sight"},
    {"MarzGuns.Rem700_Sling", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMRem700_Sling"},
    {"MarzGuns.SR7_Light", 130, nil, nil, nil, nil, nameOverrideKey="NameGoMSR7_Light"},
    {"MarzGuns.STEVENS_555_Barrel_Close", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMSTEVENS_555_Barrel_Close"},
    {"MarzGuns.STEVENS_555_Barrel_Open", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMSTEVENS_555_Barrel_Open"},
    {"MarzGuns.STEVENS_555_Barrel_Sawnoff_Close", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMSTEVENS_555_Barrel_Sawnoff_Close"},
    {"MarzGuns.STEVENS_555_Barrel_Sawnoff_Open", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMSTEVENS_555_Barrel_Sawnoff_Open"},
    {"MarzGuns.Shellholder", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMShellholder"},
    {"MarzGuns.Shh9_Suppressor", 150, nil, nil, nil, nil, nameOverrideKey="NameGoMShh9_Suppressor"},
    {"MarzGuns.Sniper_Mount", 70, nil, nil, nil, nil, nameOverrideKey="NameGoMSniper_Mount"},
    {"MarzGuns.Stub_Foregrip", 90, nil, nil, nil, nil, nameOverrideKey="NameGoMStub_Foregrip"},
    {"MarzGuns.TA28_Scope", 210, nil, nil, nil, nil, nameOverrideKey="NameGoMTA28_Scope"},
    {"MarzGuns.TL_Light", 120, nil, nil, nil, nil, nameOverrideKey="NameGoMTL_Light"},
    {"MarzGuns.TOZ34_Barrel_Close", 90, nil, nil, nil, nil, nameOverrideKey="NameGoMTOZ34_Barrel_Close"},
    {"MarzGuns.TOZ34_Barrel_Open", 140, nil, nil, nil, nil, nameOverrideKey="NameGoMTOZ34_Barrel_Open"},
    {"MarzGuns.TOZ34_Barrel_Sawnoff_Close", 150, nil, nil, nil, nil, nameOverrideKey="NameGoMTOZ34_Barrel_Sawnoff_Close"},
    {"MarzGuns.TOZ34_Barrel_Sawnoff_Open", 150, nil, nil, nil, nil, nameOverrideKey="NameGoMTOZ34_Barrel_Sawnoff_Open"},
    {"MarzGuns.TR-1_Laser", 110, nil, nil, nil, nil, nameOverrideKey="NameGoMTR-1_Laser"},
    {"MarzGuns.TR06X_Scope", 160, nil, nil, nil, nil, nameOverrideKey="NameGoMTR06X_Scope"},
    {"MarzGuns.Trix42_Muzzlebreak", 110, nil, nil, nil, nil, nameOverrideKey="NameGoMTrix42_Muzzlebreak"},
    {"MarzGuns.VP70M_Stock", 110, nil, nil, nil, nil, nameOverrideKey="NameGoMVP70M_Stock"},
    {"MarzGuns.MASTERKEY", 190, nil, nil, nil, nil, nameOverrideKey="NameGoMMASTERKEY"},
})

LS.addModdedItems({ id = "GunsOfMarz" }, "resource", "DescResource", "Recurso ou ferramenta", {
    {"MarzGuns.RepairPack", 110, nil, nil, nil, nil, nameOverrideKey="NameGoMRepairPack"},
})

-- ===================================================================
-- Modded content: Bicycle (id "BicycleMod", author RedChili, Workshop
-- 3461415167). NOT a real PZ vehicle script -- confirmed by reading its
-- own scripts: the bicycle is a carryable/pushable ItemType=base:weapon
-- (RequiresEquippedBothHands, TwoHandWeapon), so every entry below is
-- kind="item" like a normal product, just filed under category="vehicle"
-- (a pure browsing tag -- LasciviousShop_Window.lua only branches on
-- product.kind for the 3D vehicle-preview scene, never on category, so a
-- kind="item" product in the vehicle tab renders with a normal icon, no
-- risk of trying to spin up a vehicle scene for a non-vehicle script).
--
-- Two colour variants of the same bicycle (Bicycle, Bicycle_RedStreet),
-- 4 wheels (Street/Offroad x Front/Rear), and accessories.
--
-- Only the two ridable frames live in category="vehicle" -- explicit
-- request, a headlamp or a bell isn't something you go anywhere on, so
-- parts/accessories stay "other" only, no extraCategories cross-listing
-- into the Vehicles tab.
--
-- Excluded on purpose (confirmed in the mod's own Lua, not guessed):
-- - 4 "*FlatItem" wheel variants: automatic puncture-damage state, the
--   swap itself is server-driven (BicycleSyncServer.lua normalToFlat
--   table) and BicycleDebug.spawnFlatWheel lives in literally Debug.lua.
-- - Bicycle_KickstandUp / Bicycle_KickstandDown: automatic mount/dismount
--   toggle (BicycleKickstand.ensureState(bikeItem, player, "up"/"down")),
--   never something a player equips by choice.
-- - All 36 "*InSidecar" animal items (chick/chicken/cockerel/raccoon/lamb/
--   piglet/horse breeds/rabbit/turkey): system-managed visual swap for
--   when a real live animal is stowed in the sidecar (see shared/Bicycle/
--   SidecarAnimal.lua's breed->item table and BicycleStowAnimalAction.lua)
--   -- selling these would let a player fake-own a sidecar animal with no
--   real animal ever involved.
-- - The 7 raw "base:container" items (Basket, Crate, Sidecar, Saddlebag,
--   PlasticBagLeft/Right, ToolboxContainer): auto-created/linked by the
--   mod once the matching "Bicycle_X" weaponpart is attached (confirmed
--   via BicycleMenu.lua's BicycleAttachments.FindFloorItem calls) --
--   never placed in world loot themselves. Only the "Bicycle_X" attachment
--   items are (confirmed against every server/Items/Distributions_*.lua)
--   so only those are sold; the linked container comes along automatically.
--
-- No PTBR translation shipped by the mod at all (EN only) -- every entry
-- below carries nameOverrideKey/descKey resolving from Translate/EN and
-- Translate/PTBR UI.json, same safe mechanism as the PSR and GoM batches.
LS.addModdedItems({ id = "BicycleMod" }, "vehicle", "DescBicycle", "Bicicleta funcional, pronta para pedalar.", {
    {"Bicycle.Bicycle", 450, nil, nil, "DescBikeBicycle", "Bicicleta funcional, pronta para pedalar.", nameOverrideKey="NameBikeBicycle"},
    {"Bicycle.Bicycle_RedStreet", 480, nil, nil, "DescBikeBicycle_RedStreet", "Bicicleta funcional, pronta para pedalar.", nameOverrideKey="NameBikeBicycle_RedStreet"},
})
LS.addModdedItems({ id = "BicycleMod" }, "other", "DescBicyclePart", "Peca ou acessorio de bicicleta", {
    {"Bicycle.Bicycle_StreetWheelFrontItem", 90, nil, nil, "DescBikeBicycle_StreetWheelFrontItem", "Roda de bicicleta para uso na rua.", nameOverrideKey="NameBikeBicycle_StreetWheelFrontItem"},
    {"Bicycle.Bicycle_StreetWheelRearItem", 90, nil, nil, "DescBikeBicycle_StreetWheelRearItem", "Roda de bicicleta para uso na rua.", nameOverrideKey="NameBikeBicycle_StreetWheelRearItem"},
    {"Bicycle.Bicycle_OffroadWheelFrontItem", 120, nil, nil, "DescBikeBicycle_OffroadWheelFrontItem", "Roda de bicicleta para terrenos irregulares.", nameOverrideKey="NameBikeBicycle_OffroadWheelFrontItem"},
    {"Bicycle.Bicycle_OffroadWheelRearItem", 120, nil, nil, "DescBikeBicycle_OffroadWheelRearItem", "Roda de bicicleta para terrenos irregulares.", nameOverrideKey="NameBikeBicycle_OffroadWheelRearItem"},
    {"Bicycle.Bicycle_Saddlebag", 90, nil, nil, "DescBikeBicycle_Saddlebag", "Bolsa lateral para o quadro da bicicleta.", nameOverrideKey="NameBikeBicycle_Saddlebag"},
    {"Bicycle.Bicycle_Pedals", 60, nil, nil, "DescBikeBicycle_Pedals", "Par de pedais para bicicleta.", nameOverrideKey="NameBikeBicycle_Pedals"},
    {"Bicycle.Bicycle_Chain", 50, nil, nil, "DescBikeBicycle_Chain", "Corrente de transmissao da bicicleta.", nameOverrideKey="NameBikeBicycle_Chain"},
    {"Bicycle.Bicycle_Lamp", 70, nil, nil, "DescBikeBicycle_Lamp", "Farol de bicicleta, precisa de bateria.", nameOverrideKey="NameBikeBicycle_Lamp"},
    {"Bicycle.Bicycle_Bell", 30, nil, nil, "DescBikeBicycle_Bell", "Campainha de bicicleta.", nameOverrideKey="NameBikeBicycle_Bell"},
    {"Bicycle.Bicycle_Basket", 90, nil, nil, "DescBikeBicycle_Basket", "Cesta dianteira para a bicicleta.", nameOverrideKey="NameBikeBicycle_Basket"},
    {"Bicycle.Bicycle_Crate", 100, nil, nil, "DescBikeBicycle_Crate", "Caixote de carga para a bicicleta.", nameOverrideKey="NameBikeBicycle_Crate"},
    {"Bicycle.Bicycle_PlasticBagLeft", 40, nil, nil, "DescBikeBicycle_PlasticBagLeft", "Sacola improvisada para a bicicleta.", nameOverrideKey="NameBikeBicycle_PlasticBagLeft"},
    {"Bicycle.Bicycle_PlasticBagRight", 40, nil, nil, "DescBikeBicycle_PlasticBagRight", "Sacola improvisada para a bicicleta.", nameOverrideKey="NameBikeBicycle_PlasticBagRight"},
    {"Bicycle.Bicycle_BottleHolder", 25, nil, nil, "DescBikeBicycle_BottleHolder", "Suporte de garrafa para a bicicleta.", nameOverrideKey="NameBikeBicycle_BottleHolder"},
    {"Bicycle.Bicycle_Toolbox", 110, nil, nil, "DescBikeBicycle_Toolbox", "Caixa de ferramentas para a bicicleta.", nameOverrideKey="NameBikeBicycle_Toolbox"},
    {"Bicycle.Bicycle_TapedFlashlight", 55, nil, nil, "DescBikeBicycle_TapedFlashlight", "Lanterna presa com fita na bicicleta.", nameOverrideKey="NameBikeBicycle_TapedFlashlight"},
    {"Bicycle.Bicycle_TapedImprovisedFlashlight", 45, nil, nil, "DescBikeBicycle_TapedImprovisedFlashlight", "Lanterna improvisada presa com fita na bicicleta.", nameOverrideKey="NameBikeBicycle_TapedImprovisedFlashlight"},
    {"Bicycle.Bicycle_Sportsbottle", 20, nil, nil, "DescBikeBicycle_Sportsbottle", "Garrafa esportiva para a bicicleta.", nameOverrideKey="NameBikeBicycle_Sportsbottle"},
    {"Bicycle.Bicycle_SidecarRed", 260, nil, nil, "DescBikeBicycle_SidecarRed", "Sidecar lateral para a bicicleta.", nameOverrideKey="NameBikeBicycle_SidecarRed"},
    {"Bicycle.Bicycle_SidecarSpiffo", 260, nil, nil, "DescBikeBicycle_SidecarSpiffo", "Sidecar lateral para a bicicleta.", nameOverrideKey="NameBikeBicycle_SidecarSpiffo"},
    {"Bicycle.Bicycle_SidecarWhite", 260, nil, nil, "DescBikeBicycle_SidecarWhite", "Sidecar lateral para a bicicleta.", nameOverrideKey="NameBikeBicycle_SidecarWhite"},
    {"Bicycle.Bicycle_SidecarPink", 260, nil, nil, "DescBikeBicycle_SidecarPink", "Sidecar lateral para a bicicleta.", nameOverrideKey="NameBikeBicycle_SidecarPink"},
    {"Bicycle.Bicycle_SidecarBlack", 260, nil, nil, "DescBikeBicycle_SidecarBlack", "Sidecar lateral para a bicicleta.", nameOverrideKey="NameBikeBicycle_SidecarBlack"},
    {"Bicycle.Bicycle_SidecarBlue", 260, nil, nil, "DescBikeBicycle_SidecarBlue", "Sidecar lateral para a bicicleta.", nameOverrideKey="NameBikeBicycle_SidecarBlue"},
})

-- Priced entirely by LS.XP_LEVEL_UP_COST (see LasciviousShop_Shared.lua) --
-- flat per level, same for every perk/category. No per-perk or per-category
-- price argument here anymore.
local function addXPProducts(skillIcon, entries)
    for _, entry in ipairs(entries) do
        local perk = entry[1]
        table.insert(LS.PRODUCTS, {
            id="xp_" .. string.lower(perk), category="xp", kind="xp", perk=perk,
            skillIcon=skillIcon, xp=100, quantity=1,
            fallback="XP — " .. entry[2], descKey="DescXP", descFallback="+100 XP",
        })
    end
end

-- Every trainable Build 42 perk. The parent headings (Combat, Crafting,
-- Survivalist, PhysicalCategory, Agility and FarmingCategory) are intentionally
-- omitted because the game does not store XP or levels on those headings.
addXPProducts("xp-physical", {
    {"Fitness", "Condicionamento"}, {"Strength", "Força"},
    {"Lightfoot", "Passos leves"}, {"Nimble", "Agilidade"},
    {"Sprinting", "Corrida"}, {"Sneak", "Furtividade"},
})

addXPProducts("xp-melee", {
    {"Axe", "Machados"}, {"Blunt", "Contundentes longas"},
    {"SmallBlunt", "Contundentes curtas"}, {"LongBlade", "Lâminas longas"},
    {"SmallBlade", "Lâminas curtas"}, {"Spear", "Lanças"},
    {"Maintenance", "Manutenção"},
})

addXPProducts("xp-firearms", {
    {"Aiming", "Pontaria"}, {"Reloading", "Recarga"},
})

addXPProducts("xp-crafting", {
    {"Woodwork", "Carpintaria"}, {"Carving", "Entalhe"}, {"Cooking", "Culinária"},
    {"Electricity", "Eletricidade"}, {"Glassmaking", "Vidraçaria"},
    {"FlintKnapping", "Lascamento de pedra"}, {"Masonry", "Alvenaria"},
    {"Blacksmith", "Ferraria"}, {"Mechanics", "Mecânica"}, {"Pottery", "Olaria"},
    {"Tailoring", "Costura"}, {"MetalWelding", "Metalurgia"},
})

addXPProducts("xp-survival", {
    {"Doctor", "Primeiros socorros"}, {"Fishing", "Pesca"},
    {"PlantScavenging", "Coleta"}, {"Tracking", "Rastreamento"},
    {"Trapping", "Armadilhas"},
})

addXPProducts("xp-farming", {
    {"Farming", "Agricultura"}, {"Husbandry", "Criação de animais"},
    {"Butchering", "Abate"},
})

LS.PRODUCT_BY_ID = {}
LS.XP_PRODUCTS = {}
for _, product in ipairs(LS.PRODUCTS) do
    LS.PRODUCT_BY_ID[product.id] = product
    if product.kind == "xp" then LS.XP_PRODUCTS[#LS.XP_PRODUCTS + 1] = product end
end

function LS.productInCategory(product, categoryId)
    if not product or not categoryId then return false end
    if product.category == categoryId then return true end
    for _, extraCategory in ipairs(product.extraCategories or {}) do
        if extraCategory == categoryId then return true end
    end
    return false
end

local nativeNameCache = {}
local nativePerkNameCache = {}
local nativeVehicleNameCache = {}

-- Vanilla's own vehicle spawn/debug tooling (ISSpawnVehicleUI.lua) resolves
-- the player-facing vehicle name the same way: getText("IGUI_VehicleName" ..
-- script:getName()), a translation key vanilla ships for every vehicle.
local function nativeVehicleName(fullType)
    if not fullType or not getText then return nil end
    local cached = nativeVehicleNameCache[fullType]
    if cached ~= nil then return cached ~= false and cached or nil end
    local ok, value = pcall(function()
        local shortName = string.match(fullType, "%.([^.]+)$") or fullType
        local key = "IGUI_VehicleName" .. shortName
        local text = getText(key)
        if text and text ~= key then return text end
        return nil
    end)
    if ok and type(value) == "string" and value ~= "" then
        nativeVehicleNameCache[fullType] = value
        return value
    end
    nativeVehicleNameCache[fullType] = false
    return nil
end

local function nativeItemName(fullType)
    if not fullType or not getScriptManager then return nil end
    local cached = nativeNameCache[fullType]
    if cached ~= nil then return cached ~= false and cached or nil end
    local ok, value = pcall(function()
        local item = getScriptManager():FindItem(fullType)
        return item and item:getDisplayName() or nil
    end)
    if ok and type(value) == "string" and value ~= "" then
        nativeNameCache[fullType] = value
        return value
    end
    nativeNameCache[fullType] = false
    return nil
end

local function nativePerkName(perkName)
    if not perkName or not Perks or not Perks.FromString
        or not PerkFactory or not PerkFactory.getPerkName then return nil end
    local cached = nativePerkNameCache[perkName]
    if cached ~= nil then return cached ~= false and cached or nil end
    local ok, value = pcall(function()
        local perk = Perks.FromString(perkName)
        if not perk or perk == Perks.None or perk == Perks.MAX then return nil end
        return PerkFactory.getPerkName(perk)
    end)
    if ok and type(value) == "string" and value ~= "" then
        nativePerkNameCache[perkName] = value
        return value
    end
    nativePerkNameCache[perkName] = false
    return nil
end

function LS.productName(product)
    if not product then return "?" end
    if product.nameOverrideKey then return LS.text(product.nameOverrideKey, product.nameOverride) end
    if product.nameOverride then return product.nameOverride end
    if product.kind == "item" then
        local name = nativeItemName(product.fullType)
        if name then return name end
    elseif product.kind == "xp" then
        local name = nativePerkName(product.perk)
        if name then return "XP — " .. name end
    elseif product.kind == "vehicle" then
        local name = nativeVehicleName(product.fullType)
        if name then return name end
    end
    return LS.text(product.nameKey, product.fallback)
end

function LS.productDescription(product, xpAmount, perkLevel)
    if product and product.kind == "xp" and xpAmount then
        local targetLevel = math.min(10, math.max(1, math.floor(tonumber(perkLevel) or 0) + 1))
        return LS.text("DescXPScaled", "XP para alcançar o nível %1", tostring(targetLevel))
    end
    return product and LS.text(product.descKey, product.descFallback) or ""
end
