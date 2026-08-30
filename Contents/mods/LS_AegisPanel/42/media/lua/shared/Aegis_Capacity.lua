-- Admin-set storage capacities. The stamp lives in modData
-- (world object: aegisCapacity, vehicle part modData: aegisCapacity)
-- and is re-applied here on both sides whenever the engine re-derives
-- capacity from sprite properties or the installed part item.
AegisCapacity = AegisCapacity or {}

-- the engine caps a world container at 100 when READING it back
-- (ItemContainer.getCapacity, measured), so anything above that is
-- carried by the stamp and the lua override alone. Writing the raw value
-- into the field therefore changes nothing and only makes the engine
-- warn "Attempting to set capacity over maximum" once per apply. Clamp
-- the setter, keep the stamp: identical behaviour, quiet log
local WORLD_MAX = 100
-- bags are capped at 50 the same way, vehicle parts at 1000
local BAG_MAX = 50

-- the one place that writes the field, so every caller stays quiet and
-- the reasoning lives in a single spot
function AegisCapacity.setField(container, value)
    if not container or not value then return end
    pcall(function()
        local limit = WORLD_MAX
        if container:getVehiclePart() then
            limit = 1000
        elseif container:getContainingItem() then
            limit = BAG_MAX
        end
        container:setCapacity(math.min(value, limit))
    end)
end

-- world object: one stamp per object, applied to all of its containers
-- (fridge+freezer combos carry two)
function AegisCapacity.applyObject(obj)
    local ok = pcall(function()
        if not obj:hasModData() then return end
        local value = tonumber(obj:getModData().aegisCapacity)
        if not value then return end
        for i = 0, obj:getContainerCount() - 1 do
            AegisCapacity.setField(obj:getContainerByIndex(i), value)
        end
    end)
    return ok
end

function AegisCapacity.applyPart(part)
    pcall(function()
        if not part:hasModData() then return end
        local value = tonumber(part:getModData().aegisCapacity)
        if value and part:getItemContainer() then
            part:setContainerCapacity(value)
        end
    end)
end

function AegisCapacity.applyVehicle(car)
    pcall(function()
        for i = 0, car:getPartCount() - 1 do
            local part = car:getPartByIndex(i)
            if part then AegisCapacity.applyPart(part) end
        end
    end)
end

-- chunk load on either side: capacity is serialized with the container,
-- but sprite-derived rebuilds (createContainersFromSpriteProperties) can
-- fall back to the script value, so the stamp always wins
Events.LoadGridsquare.Add(function(square)
    local objects = square:getObjects()
    if not objects then return end
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj and obj:hasModData() and obj:getModData().aegisCapacity then
            AegisCapacity.applyObject(obj)
        end
    end
end)
