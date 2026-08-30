local proceduralPlaces = {
    PoliceStorageOutfit = 1,
    PoliceLockers = 1,
    ArmyStorageOutfit = 5,
    LockerArmyBedroom = 5,
    FirearmWeapons = 2,
    PawnShopGunsSpecial = 2,
    ArmySurplusOutfit = 5,
    GunStoreShelf = 1,
    CampingStoreGear = 1,
    CampingStoreBackpacks = 1,
    WardrobeRedneck = 1,
}

local suburbsPlaces = {
    ["SurvivorCache1.SurvivorCrate"] = 0.5,
    ["SurvivorCache2.SurvivorCrate"] = 0.5,
    Bag_WeaponBag = 0.5,
    Bag_SurvivorBag = 0.5,
}

local vehiclePlaces = {
    ["Police.TruckBed"] = 0.5,
    SurvivalistTruckBed = 0.5,
    HunterTruckBed = 0.5,
}

local function splitDistributionKey(key)
    local dot = string.find(key, ".", 1, true)
    if not dot then return key, nil end
    return string.sub(key, 1, dot - 1), string.sub(key, dot + 1)
end

local function addItem(items, fullType, weight)
    if not items then return end
    table.insert(items, fullType)
    table.insert(items, weight)
end

for key, weight in pairs(proceduralPlaces) do
    local distribution = ProceduralDistributions and ProceduralDistributions.list and ProceduralDistributions.list[key]
    addItem(distribution and distribution.items, "Base.AliceWeaponSling", weight)
end

for key, weight in pairs(suburbsPlaces) do
    local first, second = splitDistributionKey(key)
    local distribution = SuburbsDistributions and SuburbsDistributions[first]
    if second and distribution then
        distribution = distribution[second]
    end
    addItem(distribution and distribution.items, "Base.AliceWeaponSling", weight)
end

for key, weight in pairs(vehiclePlaces) do
    local first, second = splitDistributionKey(key)
    local distribution = VehicleDistributions and VehicleDistributions[first]
    if second and distribution then
        distribution = distribution[second]
    end
    addItem(distribution and distribution.items, "Base.AliceWeaponSling", weight)
end