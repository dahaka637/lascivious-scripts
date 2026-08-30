local HotbarCompatibility = {}
local Catalog = require "sbfplus/itemcatalog"

local SBFPLUS_ATTACHMENT_TYPES = {}
local knownAttachmentTypes = {}

local function addAttachmentType(attachmentType)
    if type(attachmentType) ~= "string" or attachmentType:sub(1, 8) ~= "SBFPlus_" then return end
    if knownAttachmentTypes[attachmentType] then return end
    knownAttachmentTypes[attachmentType] = true
    SBFPLUS_ATTACHMENT_TYPES[#SBFPLUS_ATTACHMENT_TYPES + 1] = attachmentType
end

local function addCatalogEntries(entries)
    for _, entry in ipairs(entries or {}) do
        addAttachmentType(entry.attachmentType)
        addAttachmentType(entry.betterAttachmentType)
    end
end

addCatalogEntries(Catalog.vanilla)
addCatalogEntries(Catalog.authenticZ)
addCatalogEntries(Catalog.betterFlashlights)

local function isPARFlashlightDefinition(definition, parSlotNames)
    if type(definition) ~= "table" or type(definition.type) ~= "string" then return false end
    if type(parSlotNames) ~= "table" or parSlotNames[definition.type] == nil then return false end
    if definition.type:sub(-10) ~= "Flashlight" then return false end
    return type(definition.attachments) == "table" and definition.attachments.Flashlight ~= nil
end

function HotbarCompatibility.patchPARDefinitions(definitions, parSlotNames)
    if type(definitions) ~= "table" or type(parSlotNames) ~= "table" then return 0 end

    local added = 0
    for _, definition in ipairs(definitions) do
        if isPARFlashlightDefinition(definition, parSlotNames) then
            local attachments = definition.attachments
            local genericPoint = attachments.Flashlight
            local militaryPoint = attachments.MilitaryFlashlight or genericPoint

            for _, attachmentType in ipairs(SBFPLUS_ATTACHMENT_TYPES) do
                if attachments[attachmentType] == nil then
                    attachments[attachmentType] = attachmentType == "SBFPlus_AZMilitary" and militaryPoint or genericPoint
                    added = added + 1
                end
            end
        end
    end

    return added
end

return HotbarCompatibility
