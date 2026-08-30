require "Items/ProceduralDistributions"

local function addToDistribution(name, itemFullType, weight)
    local distribution = ProceduralDistributions.list[name]
    if distribution and distribution.items then
        table.insert(distribution.items, itemFullType)
        table.insert(distribution.items, weight)
    end
end

addToDistribution("GunStoreShelf", "Base.Silencer", 3)
addToDistribution("GunStoreCounter", "Base.Silencer", 6)
addToDistribution("GunStoreDisplayCase", "Base.Silencer", 7)
addToDistribution("GunStoreMagazineRack", "Base.Silencer", 0.1)
addToDistribution("PoliceLockers", "Base.Silencer", 5)
addToDistribution("PoliceStorageGuns", "Base.Silencer", 5)
addToDistribution("PawnShopGuns", "Base.Silencer", 1)
addToDistribution("PawnShopGunsSpecial", "Base.Silencer", 1)
addToDistribution("CrateTools", "Base.Silencer", 0.03)
addToDistribution("ShelfGeneric", "Base.Silencer", 0.03)
addToDistribution("MechanicShelfMisc", "Base.Silencer", 0.03)
addToDistribution("CrateRandomJunk", "Base.Silencer", 0.03)

