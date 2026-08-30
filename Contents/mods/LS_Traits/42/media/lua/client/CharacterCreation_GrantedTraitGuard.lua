-- Vanilla gap: CharacterCreationProfession lets a trait added via another
-- trait's GrantedTraits (e.g. RegretNothing -> Smoker/Desensitized) sit as an
-- ordinary, independently-selectable/removable row in listboxTraitSelected.
-- addTrait()'s grant loop only calls listboxTraitSelected:addUniqueItem(...)
-- for a granted trait -- it never touches pointToSpend, since the grant is
-- supposed to be free. But removeTrait() has no way to tell "this row's cost
-- was never charged" from "this was bought normally": it unconditionally runs
-- pointToSpend = pointToSpend + trait:getCost() for whatever row the player
-- clicks in that list. A granted row looks identical to a manually-picked
-- one, so clicking it directly applies a refund that was never owed --
-- confirmed against vanilla's own CharacterCreationProfession.lua source,
-- not something this pack broke. Two independent guards below close it for
-- ANY trait using GrantedTraits, not just RegretNothing -- traits.txt is free
-- to add more of these later without this file needing to change.
--
-- CoopCharacterCreationProfession derives from CharacterCreationProfession
-- via :derive() and does not override isTraitExcluded/removeTrait, so
-- patching the base class here covers solo and coop character creation both
-- (same reasoning LFS_LegacyClient.lua's PointToSpend patch already relies
-- on for its own single patch site).
if isServer() then return end

local function buildGrantedLabels()
    local labels = {}
    pcall(function()
        local traitList = CharacterTraitDefinition.getTraits()
        for i = 0, traitList:size() - 1 do
            local trait = traitList:get(i)
            local grants = trait:getGrantedTraits()
            for g = 0, grants:size() - 1 do
                local grantedDef = CharacterTraitDefinition.getCharacterTraitDefinition(grants:get(g))
                if grantedDef then labels[grantedDef:getLabel()] = true end
            end
        end
    end)
    return labels
end

local grantedLabels = nil

local function isGrantedElsewhere(trait)
    if not trait then return false end
    if not grantedLabels then grantedLabels = buildGrantedLabels() end
    return grantedLabels[trait:getLabel()] == true
end

local function installGuard(cls)
    if type(cls) ~= "table" then return false end
    if type(cls.isTraitExcluded) ~= "function" or type(cls.removeTrait) ~= "function" then
        return false
    end

    -- 1) Never OFFER a granted-elsewhere trait as an independent pick, good
    -- or bad pool alike -- it should only ever be reachable via the trait
    -- that grants it.
    if not cls._lsGrantedGuardIsTraitExcludedOriginal then
        cls._lsGrantedGuardIsTraitExcludedOriginal = cls.isTraitExcluded
        cls.isTraitExcluded = function(self, trait)
            if isGrantedElsewhere(trait) then return true end
            return cls._lsGrantedGuardIsTraitExcludedOriginal(self, trait)
        end
    end

    -- 2) Belt and suspenders: even if a granted trait's row is ever clicked
    -- directly in listboxTraitSelected, refuse the point refund -- removing
    -- the GRANTING trait is the only way to drop it, exactly like vanilla
    -- already treats trait:isFree() traits.
    if not cls._lsGrantedGuardRemoveTraitOriginal then
        cls._lsGrantedGuardRemoveTraitOriginal = cls.removeTrait
        cls.removeTrait = function(self, index)
            local item = self.listboxTraitSelected and self.listboxTraitSelected:getItem(index)
            local trait = item and item.item
            if trait and self.freeTraits and self.freeTraits.contains
                and self.freeTraits:contains(trait:getLabel()) then
                return
            end
            return cls._lsGrantedGuardRemoveTraitOriginal(self, index)
        end
    end

    return true
end

local function installAll()
    pcall(require, "OptionScreens/CharacterCreationProfession")
    return installGuard(rawget(_G, "CharacterCreationProfession"))
end

if not installAll() and Events.OnTick then
    local attempts = 0
    local tick
    tick = function()
        attempts = attempts + 1
        if installAll() or attempts >= 120 then
            Events.OnTick.Remove(tick)
        end
    end
    Events.OnTick.Add(tick)
end
