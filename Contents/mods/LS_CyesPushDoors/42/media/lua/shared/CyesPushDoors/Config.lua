CyesPushDoors = CyesPushDoors or {}
CyesPushDoors.Config = CyesPushDoors.Config or {}

local C = CyesPushDoors.Config

C.VERSION = "1.0.2"
C.DEBUG = false
C.DEBUG_LABEL = "v1.0.2"

C.DOOR_ID_DIAGNOSTIC = false

C.SPECIAL_SLIDING_DOOR_SPRITES = {
    ["fixtures_doors_01_108"] = true,
    ["fixtures_doors_01_109"] = true,
    ["fixtures_doors_01_110"] = true,
    ["fixtures_doors_01_111"] = true,
    ["fixtures_doors_01_118"] = true,
    ["fixtures_doors_01_119"] = true,
}

C.DOOR_PROFILE_BY_SPRITE = {
    ["fixtures_doors_01_32"] = "reinforced",
    ["fixtures_doors_01_33"] = "reinforced",
    ["fixtures_doors_01_34"] = "reinforced",
    ["fixtures_doors_01_35"] = "reinforced",

    ["fixtures_doors_01_52"] = "resistant",
    ["fixtures_doors_01_53"] = "resistant",
    ["fixtures_doors_01_54"] = "resistant",
    ["fixtures_doors_01_55"] = "resistant",
    ["fixtures_doors_01_56"] = "resistant",
    ["fixtures_doors_01_57"] = "resistant",
    ["fixtures_doors_01_58"] = "resistant",
    ["fixtures_doors_01_59"] = "resistant",
    ["fixtures_doors_01_60"] = "resistant",
    ["fixtures_doors_01_61"] = "resistant",
    ["fixtures_doors_01_62"] = "resistant",
    ["fixtures_doors_01_63"] = "resistant",
    ["fixtures_doors_01_64"] = "resistant",
    ["fixtures_doors_01_65"] = "resistant",
    ["fixtures_doors_01_66"] = "resistant",
    ["fixtures_doors_01_67"] = "resistant",
    ["fixtures_doors_02_48"] = "resistant",
    ["fixtures_doors_02_49"] = "resistant",
    ["fixtures_doors_02_50"] = "resistant",
    ["fixtures_doors_02_51"] = "resistant",
    ["fixtures_doors_02_52"] = "resistant",
    ["fixtures_doors_02_53"] = "resistant",
    ["fixtures_doors_02_54"] = "resistant",
    ["fixtures_doors_02_55"] = "resistant",

    ["fixtures_doors_01_36"] = "glassMajority",
    ["fixtures_doors_01_37"] = "glassMajority",
    ["fixtures_doors_01_38"] = "glassMajority",
    ["fixtures_doors_01_39"] = "glassMajority",
    ["fixtures_doors_01_40"] = "glassMajority",
    ["fixtures_doors_01_41"] = "glassMajority",
    ["fixtures_doors_01_42"] = "glassMajority",
    ["fixtures_doors_01_43"] = "glassMajority",

    ["fixtures_doors_01_48"] = "glassReinforced",
    ["fixtures_doors_01_49"] = "glassReinforced",
    ["fixtures_doors_01_50"] = "glassReinforced",
    ["fixtures_doors_01_51"] = "glassReinforced",
    ["fixtures_doors_02_40"] = "glassReinforced",
    ["fixtures_doors_02_41"] = "glassReinforced",
    ["fixtures_doors_02_42"] = "glassReinforced",
    ["fixtures_doors_02_43"] = "glassReinforced",
    ["fixtures_doors_02_44"] = "glassReinforced",
    ["fixtures_doors_02_45"] = "glassReinforced",
    ["fixtures_doors_02_46"] = "glassReinforced",
    ["fixtures_doors_02_47"] = "glassReinforced",

    ["fixtures_doors_01_68"] = "scrap",
    ["fixtures_doors_01_69"] = "scrap",
    ["fixtures_doors_01_70"] = "scrap",
    ["fixtures_doors_01_71"] = "scrap",
}

C.DOOR_PROFILE_VALUES = {
    standard = {
        zombieDamageMult = 1.00,
        playerDamageMult = 1.00,
        doorWearMult = 1.00,
    },
    glassMajority = {
        zombieDamageMult = 0.50,
        playerDamageMult = 0.55,
        doorWearMult = 1.30,
        ignoreMaterialWear = true,
    },
    glassReinforced = {
        zombieDamageMult = 0.75,
        playerDamageMult = 0.78,
        doorWearMult = 1.15,
        ignoreMaterialWear = true,
    },
    scrap = {
        zombieDamageMult = 0.85,
        playerDamageMult = 0.85,
        doorWearMult = 0.78,
        ignoreMaterialWear = true,
    },
    resistant = {
        zombieDamageMult = 1.05,
        playerDamageMult = 1.05,
        doorWearMult = 0.72,
        ignoreMaterialWear = true,
    },
    reinforced = {
        zombieDamageMult = 1.15,
        playerDamageMult = 1.15,
        doorWearMult = 0.35,
        ignoreMaterialWear = true,
    },
}

C.SLIDING_DOOR_WEAR_MULT = 1.50
C.GARAGE_DOOR_WEAR_MULT = 1.00
C.GARAGE_DOOR_DURABILITY_MULT = 0.75
C.GARAGE_ZOMBIE_WEAR_MULT = 1.25
C.GARAGE_PLAYER_WEAR_MULT = 0.75
C.GARAGE_DOOR_PLAYER_DAMAGE_MULT = 2.00




C.DOUBLE_DOOR_ZOMBIE_DAMAGE = {
    [0]  = { min=0.002, max=0.005 },
    [1]  = { min=0.009, max=0.015 },
    [2]  = { min=0.015, max=0.024 },
    [3]  = { min=0.024, max=0.036 },
    [4]  = { min=0.036, max=0.054 },
    [5]  = { min=0.060, max=0.090 },
    [6]  = { min=0.084, max=0.120 },
    [7]  = { min=0.108, max=0.156 },
    [8]  = { min=0.144, max=0.204 },
    [9]  = { min=0.204, max=0.288 },
    [10] = { min=0.300, max=0.550 },
}



C.DOUBLE_DOOR_MAX_ZOMBIE_DAMAGE_FRACTION = 0.85
C.DOUBLE_DOOR_PLAYER_DAMAGE_MULT = 0.75

C.GARAGE_DOOR_WEAR_PER_TARGET = {
    [0]  = { min=0.025, max=0.035 },
    [1]  = { min=0.027, max=0.038 },
    [2]  = { min=0.030, max=0.042 },
    [3]  = { min=0.033, max=0.047 },
    [4]  = { min=0.036, max=0.052 },
    [5]  = { min=0.040, max=0.058 },
    [6]  = { min=0.045, max=0.065 },
    [7]  = { min=0.050, max=0.072 },
    [8]  = { min=0.058, max=0.082 },
    [9]  = { min=0.068, max=0.095 },
    [10] = { min=0.080, max=0.115 },
}

C.GARAGE_FORCE_BREAK_CHANCE = {
    [0]=0.00, [1]=0.00, [2]=0.01, [3]=0.02, [4]=0.04,
    [5]=0.06, [6]=0.09, [7]=0.13, [8]=0.18, [9]=0.24, [10]=0.32,
}
C.GARAGE_FORCE_STRESS_DAMAGE = {
    [0]  = { min=0.00, max=0.00 },
    [1]  = { min=0.00, max=0.00 },
    [2]  = { min=0.02, max=0.04 },
    [3]  = { min=0.03, max=0.05 },
    [4]  = { min=0.04, max=0.07 },
    [5]  = { min=0.06, max=0.09 },
    [6]  = { min=0.08, max=0.12 },
    [7]  = { min=0.10, max=0.15 },
    [8]  = { min=0.13, max=0.19 },
    [9]  = { min=0.17, max=0.24 },
    [10] = { min=0.22, max=0.30 },
}
C.GARAGE_CONDITION_BREAK_CHANCE_MAX = 0.20
C.GARAGE_TOTAL_BREAK_CHANCE_MAX = 0.75

C.GARAGE_DOOR_ZOMBIE_DAMAGE = {
    [0]  = { min=0.08, max=0.16 },
    [1]  = { min=0.15, max=0.28 },
    [2]  = { min=0.25, max=0.45 },
    [3]  = { min=0.45, max=1.05 },
    [4]  = { min=0.65, max=1.15 },
    [5]  = { min=0.80, max=1.25 },
    [6]  = { min=0.95, max=1.35 },
    [7]  = { min=1.05, max=1.45 },
    [8]  = { min=1.15, max=1.55 },
    [9]  = { min=1.25, max=1.65 },
    [10] = { min=1.40, max=1.80 },
}

C.GARAGE_FITNESS_ARM_STRAIN_PER_TARGET = {
    [0]=40.00,
    [1]=36.00,
    [2]=32.00,
    [3]=28.00,
    [4]=24.00,
    [5]=20.00,
    [6]=18.00,
    [7]=16.00,
    [8]=14.00,
    [9]=12.00,
    [10]=10.00,
}

C.DOUBLE_DOOR_FITNESS_ARM_STRAIN_PER_TARGET = {
    [0]  = 5.00,
    [1]  = 4.20,
    [2]  = 3.80,
    [3]  = 3.40,
    [4]  = 3.00,
    [5]  = 2.40,
    [6]  = 2.00,
    [7]  = 1.65,
    [8]  = 1.30,
    [9]  = 0.90,
    [10] = 0.55,
}

C.SLIDING_DOOR_MAX_ZOMBIES = {
    [0]=1, [1]=1, [2]=1, [3]=1, [4]=1,
    [5]=2, [6]=2, [7]=2, [8]=2,
    [9]=3, [10]=3,
}

C.SLIDING_DOOR_ZOMBIE_DAMAGE = {
    [0]  = { min=0.001, max=0.003 },
    [1]  = { min=0.003, max=0.006 },
    [2]  = { min=0.004, max=0.008 },
    [3]  = { min=0.005, max=0.010 },
    [4]  = { min=0.007, max=0.012 },
    [5]  = { min=0.009, max=0.015 },
    [6]  = { min=0.011, max=0.018 },
    [7]  = { min=0.013, max=0.022 },
    [8]  = { min=0.016, max=0.028 },
    [9]  = { min=0.022, max=0.035 },
    [10] = { min=0.030, max=0.050 },
}

C.SLIDING_DOOR_STANDING_ANIMATIONS = {
    "Zombie_ShotLeg_L",
    "Zombie_ShotLeg_R",
}

C.SLIDING_DOOR_CRAWLER_ANIMATIONS = {
    "Zombie_HitReact_FloorOnFront",
    "Zombie_OnKnees_ToFloorFront",
}

C.SLIDING_DOOR_PLAYER_DAMAGE_MULT = 0.20

C.IMPACT_DEDUPE_MS = 650

C.INTERACTION_REPORT_DEDUPE_MS = 300



C.SCANNER_AFTER_INTERACTION_SUPPRESS_MS = 1000




C.SCANNER_LOCAL_INTERACTION_DISTANCE = 1.60

C.PENDING_INTERACTION_TIMEOUT_MS = 3500
C.SERVER_REPORT_WINDOW_MS = 120



C.SERVER_INTERACTION_STATE_GRACE_MS = 500
C.SERVER_DOOR_COOLDOWN_MS = 900

C.MAX_SERVER_VALIDATION_DISTANCE = 2.25

C.ZOMBIE_FINISH_HEALTH = 0.10

C.ZOMBIE_DAMAGE_VERIFY_TICKS = 5
C.ZOMBIE_HEALTH_EPSILON = 0.0005
C.ZOMBIE_HEALTH_FALLBACK = 1.0

C.AFFECTED_CAPACITY = {
    [0]  = { min=1, max=1 },
    [1]  = { min=1, max=3 },
    [2]  = { min=1, max=3 },
    [3]  = { min=1, max=3 },
    [4]  = { min=1, max=3 },
    [5]  = { min=1, max=5 },
    [6]  = { min=1, max=5 },
    [7]  = { min=1, max=5 },
    [8]  = { min=1, max=5 },
    [9]  = { min=1, max=6 },
    [10] = { all=true },
}



C.DOUBLE_DOOR_AFFECTED_CAPACITY = {
    [0]  = { min=1, max=2 },
    [1]  = { min=2, max=4 },
    [2]  = { min=2, max=4 },
    [3]  = { min=2, max=5 },
    [4]  = { min=3, max=6 },
    [5]  = { min=3, max=7 },
    [6]  = { min=4, max=8 },
    [7]  = { min=4, max=9 },
    [8]  = { min=5, max=10 },
    [9]  = { min=6, max=12 },
    [10] = { all=true },
}

C.KNOCKDOWN_CAPACITY = {
    [0]  = { min=0, max=0 },
    [1]  = { min=1, max=3 },
    [2]  = { min=1, max=3 },
    [3]  = { min=1, max=3 },
    [4]  = { min=1, max=3 },
    [5]  = { min=1, max=5 },
    [6]  = { min=1, max=5 },
    [7]  = { min=1, max=5 },
    [8]  = { min=1, max=5 },
    [9]  = { min=1, max=6 },
    [10] = { all=true },
}

C.DOUBLE_DOOR_KNOCKDOWN_CAPACITY = {
    [0]  = { min=0, max=1 },
    [1]  = { min=2, max=4 },
    [2]  = { min=2, max=4 },
    [3]  = { min=2, max=5 },
    [4]  = { min=3, max=6 },
    [5]  = { min=3, max=7 },
    [6]  = { min=4, max=8 },
    [7]  = { min=4, max=9 },
    [8]  = { min=5, max=10 },
    [9]  = { min=6, max=12 },
    [10] = { all=true },
}

C.CRAWLER_STUN_HIT_TIME = 45
C.ARM_STRAIN_USAGE_LIMIT = 20.0
C.ARM_STRAIN_THRESHOLDS = {
    light = 5.0,
    medium = 12.0,
    high = 20.0,
}

C.ARM_STRAIN_RECOVERY_MS = {
    none = 1600,
    light = 2000,
    medium = 2500,
    high = 2500,
}

C.ARM_STRAIN_DEBUFF = {
    none   = { damageMult=1.00, knockdownMult=1.00 },
    light  = { damageMult=0.90, knockdownMult=0.85 },
    medium = { damageMult=0.75, knockdownMult=0.65 },
    high   = { damageMult=0.55, knockdownMult=0.40 },
}

C.FITNESS_ARM_STRAIN_PER_TARGET = {
    [0]  = 2.50,
    [1]  = 1.00,
    [2]  = 1.00,
    [3]  = 1.00,
    [4]  = 1.00,
    [5]  = 0.45,
    [6]  = 0.45,
    [7]  = 0.45,
    [8]  = 0.45,
    [9]  = 0.18,
    [10] = 0.07,
}

C.MATERIAL_DOOR_DAMAGE_MULTIPLIER = {
    wood = 1.00,
    metal = 0.38,
}

C.STRENGTH = {
    [0]  = { zombieDamageMin=0.003, zombieDamageMax=0.008, playerDamage=0.05, doorWearMin=0.000, doorWearMax=0.000 },
    [1]  = { zombieDamageMin=0.015, zombieDamageMax=0.025, playerDamage=0.12, doorWearMin=0.015, doorWearMax=0.025 },
    [2]  = { zombieDamageMin=0.025, zombieDamageMax=0.040, playerDamage=0.18, doorWearMin=0.020, doorWearMax=0.035 },
    [3]  = { zombieDamageMin=0.040, zombieDamageMax=0.060, playerDamage=0.28, doorWearMin=0.030, doorWearMax=0.045 },
    [4]  = { zombieDamageMin=0.060, zombieDamageMax=0.090, playerDamage=0.42, doorWearMin=0.040, doorWearMax=0.060 },
    [5]  = { zombieDamageMin=0.100, zombieDamageMax=0.150, playerDamage=0.70, doorWearMin=0.120, doorWearMax=0.170 },
    [6]  = { zombieDamageMin=0.140, zombieDamageMax=0.200, playerDamage=0.95, doorWearMin=0.150, doorWearMax=0.210 },
    [7]  = { zombieDamageMin=0.180, zombieDamageMax=0.260, playerDamage=1.25, doorWearMin=0.180, doorWearMax=0.260 },
    [8]  = { zombieDamageMin=0.240, zombieDamageMax=0.340, playerDamage=1.70, doorWearMin=0.240, doorWearMax=0.350 },
    [9]  = { zombieDamageMin=0.340, zombieDamageMax=0.480, playerDamage=2.35, doorWearMin=0.420, doorWearMax=0.580 },
    [10] = { zombieDamageMin=0.480, zombieDamageMax=0.880, playerDamage=3.50, doorWearMin=0.450, doorWearMax=0.850 },
}

return CyesPushDoors.Config
