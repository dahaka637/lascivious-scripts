local group = BodyLocations.getGroup("Human")

local frontSlingLocation = ItemBodyLocation.get(ResourceLocation.of("alicesweaponsling:slingfront"))
if frontSlingLocation then
    group:getOrCreateLocation(frontSlingLocation)
end

local backSlingLocation = ItemBodyLocation.get(ResourceLocation.of("alicesweaponsling:slingback"))
if backSlingLocation then
    group:getOrCreateLocation(backSlingLocation)
end