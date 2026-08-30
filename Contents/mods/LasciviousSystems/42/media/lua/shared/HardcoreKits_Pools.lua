-- Listas brancas de itens. Todos os fullTypes abaixo foram conferidos
-- contra media/scripts/generated/items/*.txt da build 42 instalada
-- (nao sao suposicoes). HardcoreKits_Validation revalida isso em runtime
-- e ignora com seguranca qualquer entrada que nao exista mais (mod
-- removido, item renomeado etc).
--
-- v2: pools bem mais completos a pedido do usuario -- "muito mais opcoes de
-- comida, bebida, TODAS as armas de fogo, e TODAS as principais armas
-- brancas e contundentes (exceto as insignificantes)". Armas de fogo ja
-- eram exaustivas desde a v1 (as 20 armas de fogo reais da build, fora as
-- duas capguns de brinquedo). Armas brancas: expandido de ~35 pra ~124,
-- filtrando manualmente fora do jogo os itens quebrados/crus/primitivos
-- (sufixos _Broken, _Crude, _Old, variantes de osso/pedra), instrumentos
-- musicais classificados como "contundente" pelo jogo, e utensilios de
-- mesa tipo garfo/colher/faca de manteiga (o pedido explicito era "nao
-- queremos sortear um garfo como arma").
require "HardcoreKits_AdminOverrides"

HardcoreKitsPools = HardcoreKitsPools or {}

-- ================= COMIDA =================

-- enlatados fechados (precisam de abridor, exatamente como um enlatado real)
HardcoreKitsPools.FoodCanned = {
    "Base.CannedBolognese", "Base.CannedCarrots2", "Base.CannedChili",
    "Base.CannedCorn", "Base.CannedCornedBeef", "Base.CannedFruitBeverage",
    "Base.CannedFruitCocktail", "Base.CannedMushroomSoup", "Base.CannedPeaches",
    "Base.CannedPeas", "Base.CannedPineapple", "Base.CannedPotato2",
    "Base.CannedSardines", "Base.CannedTomato2", "Base.TinnedBeans",
    "Base.TinnedSoup", "Base.TunaTin",
}

-- conservas / doces em pote (Pickled Food da especificacao)
HardcoreKitsPools.FoodPickled = {
    "Base.GingerPickled", "Base.Pickles", "Base.JamFruit", "Base.JamMarmalade",
}

-- outras comidas de despensa (secas/embaladas, prontas pra comer) + frutas
-- frescas (perecivel normal, nao "extremamente" perecivel -- ok pela secao 7.2)
HardcoreKitsPools.FoodSecondary = {
    "Base.BeefJerky", "Base.Crackers", "Base.GrahamCrackers", "Base.GranolaBar",
    "Base.Peanuts", "Base.PeanutButter", "Base.Popcorn", "Base.Pretzel",
    "Base.TortillaChips", "Base.TortillaChipsBaked", "Base.Cereal", "Base.CerealBowl",
    "Base.Chocolate_Candy", "Base.ChocolateChips", "Base.CookieChocolateChip",
    "Base.Biscuit", "Base.CandyCaramels", "Base.CandyFruitSlices",
    "Base.CandyGummyfish", "Base.CandyNovapops", "Base.CandyMolasses",
    "Base.RockCandy", "Base.MintCandy", "Base.NoodleSoup", "Base.DoughnutChocolate",
    "Base.Apple", "Base.Banana", "Base.Orange", "Base.Grapes", "Base.Cherry",
    "Base.Peach", "Base.Pear", "Base.Lemon", "Base.Watermelon", "Base.Avocado",
    "Base.Mango",
}

-- ================= BEBIDA =================

-- recipiente padrao de agua: FluidContainer com Fluids fluid=Water:1.0 (cheio por padrao)
HardcoreKitsPools.DrinkWater = { "Base.WaterBottle" }

HardcoreKitsPools.DrinkOther = {
    "Base.Pop", "Base.Pop2", "Base.Pop3", "Base.PopBottle", "Base.SodaCan",
    "Base.BeerCan", "Base.BeerBottle", "Base.Whiskey", "Base.Wine", "Base.Wine2",
    "Base.JuiceBox", "Base.Milk", "Base.MilkBottle",
    "Base.JuiceCranberry", "Base.JuiceFruitpunch", "Base.JuiceGrape",
    "Base.JuiceLemon", "Base.JuiceOrange", "Base.JuiceTomato",
    "Base.JuiceBoxApple", "Base.JuiceBoxFruitpunch", "Base.JuiceBoxOrange",
}

-- ================= ARMA CORPO A CORPO =================
-- categorias = Categories real do script (base:smallblunt etc). "blade" aqui
-- combina smallblade+longblade do jogo num unico balde "cortante" da spec.
-- Excluidos manualmente: variantes _Broken/_Crude/_Old, itens de
-- osso/pedra primitivos, instrumentos musicais (classificados "contundente"
-- pelo jogo mas fora do tom hardcore), e utensilios de mesa (garfo, colher,
-- faca de manteiga -- pedido explicito do usuario).

HardcoreKitsPools.MeleeByCategory = {
    smallblunt = {
        "Base.BallPeenHammer", "Base.BallPeenHammerForged", "Base.BlockMace",
        "Base.ClubHammer", "Base.ClubHammerForged", "Base.DumbBell",
        "Base.DumbBell_Forged", "Base.Hammer", "Base.HammerForged",
        "Base.LargeHook", "Base.Mace", "Base.Morningstar_Scrap_Short",
        "Base.Nightstick", "Base.PipeWrench", "Base.Ratchet", "Base.RollingPin",
        "Base.ShortBat", "Base.ShortBat_Can", "Base.ShortBat_Nails",
        "Base.ShortBat_RakeHead", "Base.SmithingHammer", "Base.SpikedShortBat",
        "Base.WoodenMallet", "Base.Wrench",
    },
    blunt = {
        "Base.BarBell", "Base.BarBell_Forged", "Base.BaseballBat",
        "Base.BaseballBat_Can", "Base.BaseballBat_Crafted",
        "Base.BaseballBat_GardenForkHead", "Base.BaseballBat_Metal",
        "Base.BaseballBat_Metal_Bolts", "Base.BaseballBat_Nails",
        "Base.BaseballBat_RakeHead", "Base.BaseballBat_ScrapSheet",
        "Base.BaseballBat_Spiked", "Base.BlockMaul", "Base.BoltCutters",
        "Base.BucketMace_Metal", "Base.BucketMace_Wood", "Base.Crowbar",
        "Base.CrowbarForged", "Base.Cudgel_GardenForkHead", "Base.Cudgel_Nails",
        "Base.Cudgel_Railspike", "Base.Cudgel_ScrapSheet", "Base.Cudgel_Spike",
        "Base.EngineMaul", "Base.GardenForkHead", "Base.GardenForkHead_Forged",
        "Base.GardenHoe", "Base.GardenHoeForged", "Base.Golfclub", "Base.IronBar",
        "Base.KettleMace_Metal", "Base.KettleMace_Wood", "Base.LargeBranch",
        "Base.Morningstar_Scrap", "Base.RailroadSpikePuller", "Base.ScrapMaul",
        "Base.ScrapWeaponRakeHead", "Base.Shovel", "Base.Shovel2",
        "Base.Sledgehammer", "Base.Sledgehammer2", "Base.SledgehammerForged",
        "Base.SnowShovel", "Base.SpadeForged", "Base.SpadeHead", "Base.SpadeWood",
        "Base.SteelBar", "Base.StoneMaul",
    },
    blade = {
        "Base.BreadKnife", "Base.FightingKnife", "Base.HuntingKnife",
        "Base.HuntingKnifeForged", "Base.KitchenKnife", "Base.KitchenKnifeForged",
        "Base.KnifeButterfly", "Base.KnifeFillet", "Base.KnifeParing",
        "Base.KnifePocket", "Base.KnifeSushi", "Base.LargeKnife",
        "Base.LargeKnife_Scrap", "Base.MacheteKnife", "Base.RailroadSpikeKnife",
        "Base.Scalpel", "Base.Scissors", "Base.ScissorsForged", "Base.SmallKnife",
        "Base.SteakKnife", "Base.SwitchKnife",
        "Base.Katana", "Base.Machete", "Base.MacheteForged", "Base.ShortSword",
        "Base.ShortSword_Scrap", "Base.Sword", "Base.Sword_Scrap",
        -- adicionados na auditoria de 2026-08-04: cross-check contra
        -- media/scripts/generated/items/weapon.txt (todo item com
        -- Categories=base:smallblade/longblade e sem AmmoType) achou estes
        -- dois faltando -- nenhum e Crude/Old/Broken/primitivo/instrumento/
        -- utensilio (a exclusao ja aplicada em todo o resto do pool)
        "Base.HandguardDagger", "Base.IcePick",
    },
    axe = {
        "Base.Axe", "Base.Axe_Sawblade", "Base.Axe_Sawblade_Hatchet",
        "Base.Axe_ScrapCleaver", "Base.BaseballBat_Metal_Sawblade",
        "Base.BaseballBat_RailSpike", "Base.BaseballBat_Sawblade",
        "Base.EntrenchingTool", "Base.HandAxe", "Base.HandAxeForged",
        "Base.HandScythe", "Base.HandScytheForged", "Base.IceAxe",
        "Base.LongHandle_Sawblade", "Base.MeatCleaver", "Base.MeatCleaverForged",
        "Base.MeatCleaver_Scrap", "Base.PickAxe", "Base.PickAxeForged",
        "Base.WoodAxe", "Base.WoodAxeForged",
        -- mesma auditoria de 2026-08-04: uma familia inteira de armas
        -- improvisadas (cabo + serra/freio/pa/espeto encaixado) que ja
        -- tinhamos PARCIALMENTE (ex: BaseballBat_Sawblade/_RailSpike, ja
        -- acima) mas faltavam varios "irmaos" -- mesmo genero de item, mesma
        -- categoria in-game (base:axe), dano comparavel aos ja incluidos
        "Base.Cudgel_Brake", "Base.Cudgel_Sawblade", "Base.Cudgel_SpadeHead",
        "Base.MetalPipe_Railspike", "Base.Plank_Brake", "Base.Plank_Sawblade",
        "Base.ScrapWeaponGardenFork", "Base.ScrapWeaponSpade",
        "Base.ScrapWeapon_Brake", "Base.ShortBat_RailSpike",
        "Base.ShortBat_Sawblade",
    },
    spear = {
        "Base.SpearGlass", "Base.SpearLong", "Base.SpearShort",
    },
}

-- ================= ARMA DE FOGO =================
-- ammoBox = caixa de municao compativel (item real, confirmado via campo
-- AmmoBox do script da arma). magazine = carregador destacavel, quando existe
-- (confirmado via campo MagazineType). maxAmmo = capacidade total da arma
-- (campo MaxAmmo do script), usado para entregar a arma ja carregada.
-- tier = raridade, usada so na recompensa semanal. Lista EXAUSTIVA: todas as
-- 20 armas de fogo reais da build 42 (fora as duas capguns de brinquedo,
-- Revolver_CapGun e Rifle_CapGun, que nao sao armas de verdade).
HardcoreKitsPools.Firearms = {
    { fullType = "Base.Pistol",                     ammoBox = "Base.Bullets9mmBox",     magazine = "Base.9mmClip",  maxAmmo = 15, tier = "common" },
    { fullType = "Base.Revolver_Short",              ammoBox = "Base.Bullets38Box",      magazine = nil,             maxAmmo = 5,  tier = "common" },
    { fullType = "Base.Revolver",                    ammoBox = "Base.Bullets357Box",     magazine = nil,             maxAmmo = 6,  tier = "common" },
    { fullType = "Base.Pistol2",                     ammoBox = "Base.Bullets45Box",      magazine = "Base.45Clip",   maxAmmo = 7,  tier = "uncommon" },
    { fullType = "Base.Pistol3",                     ammoBox = "Base.Bullets44Box",      magazine = "Base.44Clip",   maxAmmo = 8,  tier = "uncommon" },
    { fullType = "Base.Revolver_Long",                ammoBox = "Base.Bullets44Box",      magazine = nil,             maxAmmo = 6,  tier = "uncommon" },
    { fullType = "Base.Shotgun",                     ammoBox = "Base.ShotgunShellsBox",  magazine = nil,             maxAmmo = 5,  tier = "uncommon" },
    { fullType = "Base.DoubleBarrelShotgun",         ammoBox = "Base.ShotgunShellsBox",  magazine = nil,             maxAmmo = 2,  tier = "uncommon" },
    { fullType = "Base.DoubleBarrelShotgunSawnoff",  ammoBox = "Base.ShotgunShellsBox",  magazine = nil,             maxAmmo = 2,  tier = "uncommon" },
    { fullType = "Base.ShotgunSawnoff",              ammoBox = "Base.ShotgunShellsBox",  magazine = nil,             maxAmmo = 5,  tier = "uncommon" },
    { fullType = "Base.JS3T_Shotgun",                ammoBox = "Base.ShotgunShellsBox",  magazine = nil,             maxAmmo = 7,  tier = "uncommon" },
    { fullType = "Base.HuntingRifle",                ammoBox = "Base.308Box",            magazine = nil,             maxAmmo = 4,  tier = "uncommon" },
    { fullType = "Base.MSR7T_Rifle",                 ammoBox = "Base.308Box",            magazine = nil,             maxAmmo = 4,  tier = "uncommon" },
    { fullType = "Base.VarmintRifle",                ammoBox = "Base.556Box",            magazine = nil,             maxAmmo = 5,  tier = "uncommon" },
    { fullType = "Base.L92_Carbine",                 ammoBox = "Base.Bullets357Box",     magazine = nil,             maxAmmo = 10, tier = "rare" },
    { fullType = "Base.L94_Rifle",                   ammoBox = "Base.3030Box",           magazine = nil,             maxAmmo = 6,  tier = "rare" },
    { fullType = "Base.TrapperCarbine",              ammoBox = "Base.Bullets45Box",      magazine = "Base.45Clip",   maxAmmo = 7,  tier = "rare" },
    { fullType = "Base.JS14_Rifle",                  ammoBox = "Base.556Box",            magazine = "Base.JS14_Clip",maxAmmo = 20, tier = "rare" },
    { fullType = "Base.AssaultRifle2",               ammoBox = "Base.308Box",            magazine = "Base.M14Clip",  maxAmmo = 20, tier = "rare" },
    { fullType = "Base.AssaultRifle",                ammoBox = "Base.556Box",            magazine = "Base.556Clip",  maxAmmo = 30, tier = "rare" },
}

-- caixas de municao avulsas para o sub-sorteio "municao" da recompensa semanal
-- (nao precisa corresponder a uma arma que o personagem tenha -- secao 18.1)
HardcoreKitsPools.AmmoBoxes = {
    "Base.Bullets38Box", "Base.Bullets357Box", "Base.Bullets9mmBox",
    "Base.Bullets44Box", "Base.Bullets45Box", "Base.ShotgunShellsBox",
    "Base.308Box", "Base.556Box", "Base.3030Box",
}

-- ================= ARMA DE FOGO -- GUNS OF MARZ (GoM) =================
-- Usado no lugar de HardcoreKitsPools.Firearms/AmmoBoxes quando GoMCompat.isActive()
-- (ver GoMCompat.lua e HardcoreKits_Validation.lua) -- GoM nao remove as armas
-- vanilla sozinho, entao essa troca e decisao explicita do servidor, nao uma
-- limitacao do proprio GoM. Mesmo formato exato de HardcoreKitsPools.Firearms
-- acima. ammoBox/magazine copiados direto dos campos AmmoBox/MagazineType de
-- cada arma no script do GoM (media/scripts/MarzWeapons/items/weapons/*.txt),
-- nao adivinhados -- cada referencia foi cruzada contra os itens de municao/
-- carregador que o proprio GoM define (nenhuma pendente). tier dividido em
-- tercos pelo preco calculado pra loja (ver LasciviousShop_Catalog.lua).
-- 70 das 81 armas reais do GoM: excluidas as duas variantes de "explosao" de
-- granada de 40mm (nao sao armas de fogo, ver comentario no bloco da loja) e
-- as 5 armas brancas/baioneta (essas vao soltas no catalogo da loja, categoria
-- "melee", fora deste pool de armas de fogo).
HardcoreKitsPools.GoMFirearms = {
    { fullType = "MarzGuns.AA12", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = "MarzGuns.12GMagazine8_AA12", maxAmmo = 8, tier = "uncommon" },
    { fullType = "MarzGuns.AK47", ammoBox = "MarzGuns.762x39_Box", magazine = "MarzGuns.762x39Magazine30", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.AK74", ammoBox = "MarzGuns.545x39_Box", magazine = "MarzGuns.545x39Magazine30_Bakelite", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.AKS74U", ammoBox = "MarzGuns.545x39_Box", magazine = "MarzGuns.545x39Magazine30_Bakelite", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.AR15", ammoBox = "MarzGuns.223_Box", magazine = "MarzGuns.556x45Magazine20_STANAG", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.ASVAL", ammoBox = "MarzGuns.9x39_Box", magazine = "MarzGuns.9x39Magazine30", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.BAR", ammoBox = "MarzGuns.3006_Box", magazine = "MarzGuns.3006Magazine20_BAR", maxAmmo = 20, tier = "rare" },
    { fullType = "MarzGuns.BENELLI_M4", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 7, tier = "uncommon" },
    { fullType = "MarzGuns.CAMP_CARBINE", ammoBox = "MarzGuns.45_Box", magazine = "MarzGuns.45Magazine7_M1911", maxAmmo = 7, tier = "uncommon" },
    { fullType = "MarzGuns.CAR15", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_STANAG", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.COLT_SINGLE", ammoBox = "MarzGuns.45_Box", magazine = nil, maxAmmo = 6, tier = "common" },
    { fullType = "MarzGuns.DEAGLE", ammoBox = "MarzGuns.50_Box", magazine = "MarzGuns.50Magazine8_DEAGLE", maxAmmo = 8, tier = "common" },
    { fullType = "MarzGuns.DETECTIVE_38", ammoBox = "MarzGuns.38_Box", magazine = nil, maxAmmo = 6, tier = "common" },
    { fullType = "MarzGuns.DOUBLEBARREL", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 2, tier = "common" },
    { fullType = "MarzGuns.FAL", ammoBox = "MarzGuns.762x51_Box", magazine = "MarzGuns.762x51Magazine20_FAL", maxAmmo = 20, tier = "uncommon" },
    { fullType = "MarzGuns.FAMAS", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_STANAG", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.FNC", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_STANAG", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.G3", ammoBox = "MarzGuns.762x51_Box", magazine = "MarzGuns.762x51Magazine20_G3", maxAmmo = 20, tier = "uncommon" },
    { fullType = "MarzGuns.G36", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_G36", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.G36C", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_G36", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.HIPOWER", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine13_HIPOWER", maxAmmo = 13, tier = "common" },
    { fullType = "MarzGuns.M14", ammoBox = "MarzGuns.762x51_Box", magazine = "MarzGuns.762x51Magazine20_M14", maxAmmo = 20, tier = "rare" },
    { fullType = "MarzGuns.M16A1", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_STANAG", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.M16A2", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_STANAG", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.M16A2_M203", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_STANAG", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.M16A3", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_STANAG", maxAmmo = 30, tier = "rare" },
    { fullType = "MarzGuns.M1895", ammoBox = "MarzGuns.4570_Box", magazine = nil, maxAmmo = 6, tier = "uncommon" },
    { fullType = "MarzGuns.M1903", ammoBox = "MarzGuns.3006_Box", magazine = nil, maxAmmo = 5, tier = "rare" },
    { fullType = "MarzGuns.M1911", ammoBox = "MarzGuns.45_Box", magazine = "MarzGuns.45Magazine7_M1911", maxAmmo = 7, tier = "common" },
    { fullType = "MarzGuns.M1_GARAND", ammoBox = "MarzGuns.3006_Box", magazine = "MarzGuns.3006Clip8", maxAmmo = 8, tier = "rare" },
    { fullType = "MarzGuns.M203_Weapon", ammoBox = "MarzGuns.40mm_Box_HE", magazine = nil, maxAmmo = 1, tier = "rare" },
    { fullType = "MarzGuns.M24", ammoBox = "MarzGuns.762x51_Box", magazine = nil, maxAmmo = 5, tier = "rare" },
    { fullType = "MarzGuns.M4A1", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_STANAG", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.M60", ammoBox = "MarzGuns.762x51_Box", magazine = "MarzGuns.762x51Box100_M60", maxAmmo = 100, tier = "rare" },
    { fullType = "MarzGuns.M79", ammoBox = "MarzGuns.40mm_Box_Buckshot", magazine = nil, maxAmmo = 1, tier = "rare" },
    { fullType = "MarzGuns.M92FS", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine15_M92FS", maxAmmo = 15, tier = "common" },
    { fullType = "MarzGuns.M93R", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine18_M93R", maxAmmo = 18, tier = "common" },
    { fullType = "MarzGuns.MAC10", ammoBox = "MarzGuns.45_Box", magazine = "MarzGuns.45Magazine30_MAC10", maxAmmo = 15, tier = "common" },
    { fullType = "MarzGuns.MASTERKEY_Weapon", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 5, tier = "rare" },
    { fullType = "MarzGuns.MINI_14", ammoBox = "MarzGuns.223_Box", magazine = "MarzGuns.223Magazine20_Mini14", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.MODEL_70", ammoBox = "MarzGuns.223_Box", magazine = nil, maxAmmo = 5, tier = "uncommon" },
    { fullType = "MarzGuns.MOSIN", ammoBox = "MarzGuns.762x54_Box", magazine = nil, maxAmmo = 5, tier = "rare" },
    { fullType = "MarzGuns.MOSSBERG_590", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 5, tier = "uncommon" },
    { fullType = "MarzGuns.MP412", ammoBox = "MarzGuns.38_Box", magazine = nil, maxAmmo = 5, tier = "common" },
    { fullType = "MarzGuns.MP5", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine20_MP5", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.MP5A2", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine20_MP5", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.MP5K", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine20_MP5", maxAmmo = 15, tier = "common" },
    { fullType = "MarzGuns.MP5SD", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine20_MP5", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.P226", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine10_P226", maxAmmo = 10, tier = "common" },
    { fullType = "MarzGuns.PSG1", ammoBox = "MarzGuns.762x51_Box", magazine = "MarzGuns.762x51Magazine5_PSG1", maxAmmo = 5, tier = "rare" },
    { fullType = "MarzGuns.PYTHON", ammoBox = "MarzGuns.357_Box", magazine = nil, maxAmmo = 6, tier = "common" },
    { fullType = "MarzGuns.REMINGTON_700", ammoBox = "MarzGuns.308_Box", magazine = nil, maxAmmo = 5, tier = "uncommon" },
    { fullType = "MarzGuns.REMINGTON_870", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 5, tier = "uncommon" },
    { fullType = "MarzGuns.RHINO", ammoBox = "MarzGuns.357_Box", magazine = nil, maxAmmo = 6, tier = "common" },
    { fullType = "MarzGuns.SKS", ammoBox = "MarzGuns.762x39_Box", magazine = nil, maxAmmo = 10, tier = "rare" },
    { fullType = "MarzGuns.SPAS12", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 7, tier = "uncommon" },
    { fullType = "MarzGuns.STEVENS_555", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 2, tier = "common" },
    { fullType = "MarzGuns.SVD", ammoBox = "MarzGuns.762x54_Box", magazine = "MarzGuns.762x54Magazine10_SVD", maxAmmo = 10, tier = "rare" },
    { fullType = "MarzGuns.SW629", ammoBox = "MarzGuns.44_Box", magazine = nil, maxAmmo = 5, tier = "common" },
    { fullType = "MarzGuns.TEC9", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine20_TEC9", maxAmmo = 20, tier = "common" },
    { fullType = "MarzGuns.THOMPSON", ammoBox = "MarzGuns.45_Box", magazine = "MarzGuns.45Magazine30_THOMPSON", maxAmmo = 30, tier = "uncommon" },
    { fullType = "MarzGuns.TOZ34", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 2, tier = "common" },
    { fullType = "MarzGuns.TRENCHGUN", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 5, tier = "uncommon" },
    { fullType = "MarzGuns.USP", ammoBox = "MarzGuns.45_Box", magazine = "MarzGuns.45Magazine12_USP", maxAmmo = 12, tier = "common" },
    { fullType = "MarzGuns.VP70M", ammoBox = "MarzGuns.9x19_Box", magazine = "MarzGuns.9x19Magazine18_VP70M", maxAmmo = 18, tier = "common" },
    { fullType = "MarzGuns.W1873", ammoBox = "MarzGuns.357_Box", magazine = nil, maxAmmo = 9, tier = "common" },
    { fullType = "MarzGuns.W1873_CARBINE", ammoBox = "MarzGuns.357_Box", magazine = nil, maxAmmo = 6, tier = "common" },
    { fullType = "MarzGuns.W1887", ammoBox = "MarzGuns.12Gauge_Box_Buckshot", magazine = nil, maxAmmo = 5, tier = "common" },
    { fullType = "MarzGuns.W1894", ammoBox = "MarzGuns.3030_Box", magazine = nil, maxAmmo = 6, tier = "common" },
    { fullType = "MarzGuns.XM177", ammoBox = "MarzGuns.556x45_Box", magazine = "MarzGuns.556x45Magazine30_STANAG", maxAmmo = 30, tier = "uncommon" },
}

-- caixas de municao avulsas do GoM pro sub-sorteio "municao" da recompensa
-- semanal -- exatamente as 20 caixas realmente referenciadas pelas 70 armas
-- de HardcoreKitsPools.GoMFirearms acima (deduplicadas), mesmo criterio do
-- HardcoreKitsPools.AmmoBoxes vanilla.
HardcoreKitsPools.GoMAmmoBoxes = {
    "MarzGuns.12Gauge_Box_Buckshot", "MarzGuns.223_Box", "MarzGuns.3006_Box",
    "MarzGuns.3030_Box", "MarzGuns.308_Box", "MarzGuns.357_Box",
    "MarzGuns.38_Box", "MarzGuns.40mm_Box_Buckshot", "MarzGuns.40mm_Box_HE",
    "MarzGuns.44_Box", "MarzGuns.4570_Box", "MarzGuns.45_Box",
    "MarzGuns.50_Box", "MarzGuns.545x39_Box", "MarzGuns.556x45_Box",
    "MarzGuns.762x39_Box", "MarzGuns.762x51_Box", "MarzGuns.762x54_Box",
    "MarzGuns.9x19_Box", "MarzGuns.9x39_Box",
}

-- ================= MOCHILA =================
-- todos confirmados com CanBeEquipped = base:back no script.
HardcoreKitsPools.BackpackByTier = {
    escolar = { "Base.Bag_Schoolbag", "Base.Bag_Schoolbag_Kids", "Base.Bag_Schoolbag_Patches" },
    comum = {
        "Base.Bag_DuffelBag", "Base.Bag_NormalHikingBag", "Base.Bag_Military",
        "Base.Bag_HikingBag_Travel", "Base.Bag_HydrationBackpack",
        "Base.Bag_Police", "Base.Bag_Sheriff", "Base.Bag_InmateEscapedBag",
    },
    grande = {
        "Base.Bag_BigHikingBag", "Base.Bag_CraftedFramepack_Large",
        "Base.Bag_TarpFramepack_Large", "Base.Bag_CraftedFramepack_Large2",
        "Base.Bag_SWAT",
    },
    militar = {
        "Base.Bag_ALICEpack", "Base.Bag_ALICEpack_Army", "Base.Bag_SurvivorBag",
        "Base.Bag_CraftedFramepack_Large3",
    },
}

-- ================= RECURSO / FERRAMENTA (Kit Inicial + recompensa semanal) =================
HardcoreKitsPools.Resources = {
    "Base.Screwdriver", "Base.Saw", "Base.TinOpener", "Base.Scissors",
    "Base.DuctTape", "Base.Glue", "Base.WireStack", "Base.Matches",
    "Base.Lighter", "Base.NailsBox", "Base.Rope", "Base.Sheet", "Base.Twine",
    "Base.Bandage", "Base.Disinfectant", "Base.SutureNeedle", "Base.Antibiotics",
    "Base.PillsVitamins", "Base.AlcoholWipes", "Base.FirstAidKit", "Base.SewingKit",
    -- expansao "criativa" pedida pelo usuario: mais itens medicos + utilidades
    -- que ajudam de verdade (navegacao, comunicacao, iluminacao, sinalizacao)
    "Base.Splint", "Base.Bandaid", "Base.PillsBeta", "Base.Tarp",
    "Base.Whistle", "Base.CompassDirectional", "Base.RadioBlack",
    "Base.FlashLight_AngleHead",
    -- pente-fino de 2026-08-04: cross-check contra media/scripts/generated/
    -- items/{normal,drainable,radio,weapon}.txt (DisplayCategory=FirstAid/
    -- Tool/Electronics/Communications/Camping/Household/Fishing), mesmo
    -- metodo programatico da auditoria de armas -- so itens leves,
    -- funcionais, sem tag Obsolete e sem exigir recurso externo alem do que
    -- ja resolvemos abaixo (bateria)
    -- medico
    "Base.Pills", "Base.PillsAntiDep", "Base.PillsSleepingTablets",
    "Base.Tweezers", "Base.Coldpack", "Base.CottonBalls",
    -- ferramenta geral
    "Base.Pliers", "Base.Zipties", "Base.Whetstone", "Base.Funnel",
    "Base.MagnifyingGlass",
    -- eletronica / comunicacao (WalkieTalkie2 e RadioBlack, acima, ambos
    -- exigem bateria instalada pra funcionar -- ver ResourceNeedsBatteryOnDeliver)
    "Base.Battery", "Base.WalkieTalkie2",
    -- camping / sobrevivencia
    "Base.WaterPurificationTablets", "Base.InsectRepellent",
    "Base.MagnesiumFirestarter", "Base.SleepingBag_Green_Packed",
    "Base.TentGreen_Packed",
    -- casa / higiene / seguranca
    "Base.Soap2", "Base.UmbrellaBlack", "Base.Extinguisher",
    -- pesca
    "Base.FishingRod", "Base.FishingNet",
}

-- lanterna e drainable (carga propria, sem carregador destacavel -- nao
-- confundir com o sistema de municao/carregador de arma) -- HardcoreKits_Delivery
-- garante carga cheia na entrega pra quem tirar ela no sorteio.
HardcoreKitsPools.ResourceFullChargeOnDeliver = { "Base.FlashLight_AngleHead" }

-- radio/walkie-talkie NAO funcionam sem bateria instalada (confirmado no
-- proprio script: Tags = base:usesbattery / UsesBattery = true em ambos) --
-- sem isso, RadioBlack (ja estava no pool) seria entregue inutilizavel, e o
-- novo WalkieTalkie2 tambem seria. HardcoreKits_Delivery instala uma
-- Base.Battery de verdade via deviceData:addBattery(), mesma chamada que a
-- UI vanilla usa (ver client/RadioCom/RadioWindowModules/RWMPower.lua +
-- shared/TimedActions/ISDeviceBatteryAction.lua:24) -- so sem a timed action
-- de "andar ate" e "arrastar item", que so fazem sentido pra interacao do
-- jogador, nao pra entrega server-side instantanea.
HardcoreKitsPools.ResourceNeedsBatteryOnDeliver = { "Base.RadioBlack", "Base.WalkieTalkie2" }

-- "bolsa de trauma" (Base.Bag_MedicalBag -- nome real do item em ingles e
-- "Trauma Bag", a mochila de socorrista): resultado especial e raro (chance
-- configuravel -- ver HardcoreKits_Config.InitialTraumaBagChance/
-- SurvivalTraumaBagChance). Em vez de itens avulsos, entrega essa mochila ja
-- recheada -- mesmo espirito do resto do mod: a mochila e o "vencedor"
-- exibido na roleta, o conteudo de dentro fica de surpresa pro jogador abrir
-- depois.
--
-- Historico: ate 2026-08-05 esta tabela se chamava MedicalKitBag/Contents.
-- Renomeada pra TraumaBagBag/Contents porque o usuario esclareceu que
-- "maleta medica" (o nome que ele usava) se referia a um item DIFERENTE, MENOR
-- (ver HardcoreKitsPools.MedicalKitBag/Contents logo abaixo, que agora aponta
-- pro item certo) -- os dois passaram a poder cair independentemente, cada
-- um com sua propria chance. Lista recheada de novo a pedido explicito do
-- usuario ("mais uma recheada... literalmente completinha").
HardcoreKitsPools.TraumaBagBag = "Base.Bag_MedicalBag"
HardcoreKitsPools.TraumaBagContents = {
    { fullType = "Base.Bandage", qty = 6 },
    { fullType = "Base.Bandaid", qty = 4 },
    { fullType = "Base.Disinfectant", qty = 3 },
    { fullType = "Base.AlcoholWipes", qty = 4 },
    { fullType = "Base.AlcoholBandage", qty = 2 },
    { fullType = "Base.SutureNeedle", qty = 3 },
    { fullType = "Base.Antibiotics", qty = 3 },
    { fullType = "Base.Splint", qty = 2 },
    { fullType = "Base.PillsVitamins", qty = 2 },
    { fullType = "Base.PillsBeta", qty = 1 },
    { fullType = "Base.Tweezers", qty = 1 },
    { fullType = "Base.Forceps_Forged", qty = 1 },
    { fullType = "Base.Coldpack", qty = 3 },
    { fullType = "Base.CottonBalls", qty = 3 },
}

-- "kit medico" (Base.FirstAidKit -- a maleta pequena de metal, capacidade
-- bem menor que a bolsa de trauma acima): SEGUNDO resultado especial
-- independente, pedido explicito do usuario -- era este o item que ele
-- queria dizer originalmente com "maleta medica". Recheio propositalmente
-- mais modesto que o da bolsa de trauma, condizente com o tamanho real do
-- item (Capacity=4 contra Capacity=18 da bolsa).
--
-- Conteudo em DUAS partes (pedido explicito do usuario): uma parte GARANTIDA
-- (sempre entregue, "sempre 2 bandagens no minimo") e um POOL aleatorio (so
-- os TIPOS de item, nao qty -- ver HardcoreKitsRolls.rollMedicalKitContents,
-- que sorteia quantos tipos entram e a quantidade de cada um na hora da
-- entrega, nunca a mesma combinacao duas vezes). Bandage fica de fora do
-- pool aleatorio de proposito (ja garantida acima, aqui e so variedade).
HardcoreKitsPools.MedicalKitBag = "Base.FirstAidKit"
HardcoreKitsPools.MedicalKitGuaranteed = {
    { fullType = "Base.Bandage", qty = 2 },
}
HardcoreKitsPools.MedicalKitRandomPool = {
    "Base.Bandaid", "Base.Disinfectant", "Base.AlcoholWipes", "Base.SutureNeedle",
    "Base.Antibiotics", "Base.Splint", "Base.PillsVitamins", "Base.PillsBeta",
    "Base.Tweezers", "Base.Coldpack", "Base.CottonBalls",
}

-- ================= GRUPOS DE HABILIDADE (bonus de skill) =================
-- 6 grupos cobrindo TODAS as 35 skills reais do jogo (nenhuma fica de fora,
-- pedido explicito do usuario). Hierarquia verificada direto no bytecode de
-- PerkFactory.class (nao suposta) -- o jogo agrupa em Combat/Firearm(sub)/
-- Crafting/Survivalist/PhysicalCategory/Agility(sub)/FarmingCategory; os 6
-- grupos abaixo sao a curadoria do MOD em cima disso (Agilidade dobrada
-- dentro de Fisica, First Aid dentro de Sobrevivencia -- decisao do usuario,
-- ja que ele so pediu 6 grupos no total).
--
-- Perks guardados como STRING (nome exato do enum, ex: "Axe"), NAO como
-- referencia direta a Perks.Axe -- carregar esta tabela acontece no boot do
-- mod, antes de qualquer garantia de que a tabela global `Perks` do engine
-- ja esta populada; resolver com Perks.FromString(nome) em tempo de sorteio/
-- entrega (HardcoreKits_Rolls/Delivery) evita esse risco de ordem de carga
-- por completo. labelKey e a chave de traducao PROPRIA do mod (nao existe
-- rotulo vanilla que bata exatamente com este agrupamento).
HardcoreKitsPools.SkillGroups = {
    {
        key = "melee", labelKey = "UI_HardcoreKits_SkillGroupMelee",
        perks = { "Axe", "Blunt", "SmallBlunt", "LongBlade", "SmallBlade", "Spear", "Maintenance" },
    },
    {
        key = "firearm", labelKey = "UI_HardcoreKits_SkillGroupFirearm",
        perks = { "Aiming", "Reloading" },
    },
    {
        key = "crafting", labelKey = "UI_HardcoreKits_SkillGroupCrafting",
        perks = {
            "Woodwork", "Carving", "Cooking", "Electricity", "Glassmaking",
            "FlintKnapping", "Masonry", "Blacksmith", "Mechanics", "Pottery",
            "Tailoring", "MetalWelding",
        },
    },
    {
        key = "physical", labelKey = "UI_HardcoreKits_SkillGroupPhysical",
        perks = { "Fitness", "Strength", "Sprinting", "Lightfoot", "Nimble", "Sneak" },
    },
    {
        key = "survivalist", labelKey = "UI_HardcoreKits_SkillGroupSurvivalist",
        perks = { "Fishing", "PlantScavenging", "Tracking", "Trapping", "Doctor" },
    },
    {
        key = "farming", labelKey = "UI_HardcoreKits_SkillGroupFarming",
        perks = { "Farming", "Husbandry", "Butchering" },
    },
}

-- ================= overrides do dono do servidor =================
-- edite HardcoreKits_AdminOverrides.lua, nao este arquivo, pra
-- forcar-incluir ou banir itens -- assim uma atualizacao futura do mod nao
-- apaga as customizacoes do servidor.
HardcoreKitsAdminOverrides.apply(HardcoreKitsPools)
