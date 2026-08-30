-- Shared helpers for non-invasive suppressor model mounts.
--
-- Some weapon mods use their muzzle attachment for muzzle-flash placement,
-- which may be farther forward than the visible barrel end.  Rather than
-- modifying the foreign model's existing attachments, ISIL creates its own
-- attachment and combines a verified position with the original muzzle
-- rotation.

local ISIL_ModelMounts = {}

local function ISIL_copyVector(target, source)
    target:set(source:x(), source:y(), source:z())
end

function ISIL_ModelMounts.ensure(config)
    local scriptManager = getScriptManager()
    local model = scriptManager and scriptManager:getModelScript(config.modelScript) or nil

    if not model then
        return nil, "model script is unavailable: " .. tostring(config.modelScript)
    end

    local rotationSource = model:getAttachmentById(config.rotationAttachment or "muzzle")

    if not rotationSource then
        return nil, "rotation attachment is unavailable on " .. tostring(config.modelScript)
    end

    local mount = model:getAttachmentById(config.id)

    if not mount then
        local ok, created = pcall(function()
            return ModelAttachment.new(config.id)
        end)

        if not ok or not created then
            return nil, "could not create model attachment on " .. tostring(config.modelScript)
        end

        mount = model:addAttachment(created)
    end

    if config.positionAttachment then
        local positionSource = model:getAttachmentById(config.positionAttachment)

        if not positionSource then
            return nil, "position attachment is unavailable on " .. tostring(config.modelScript)
        end

        ISIL_copyVector(mount:getOffset(), positionSource:getOffset())
    elseif config.offset then
        mount:getOffset():set(config.offset[1], config.offset[2], config.offset[3])
    else
        return nil, "no mount position was configured for " .. tostring(config.modelScript)
    end

    ISIL_copyVector(mount:getRotate(), rotationSource:getRotate())
    return config.id
end

return ISIL_ModelMounts
