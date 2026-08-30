-- Guns of Marz (GoM, mod id "GunsOfMarz") compatibility detection, shared by
-- LasciviousShop_Server.lua (hides vanilla firearm/ammo catalog entries) and
-- HardcoreKits_Validation.lua (swaps the Firearms/AmmoBoxes reward pools).
--
-- GoM does not remove vanilla firearms itself -- confirmed by reading its own
-- Distribution/ItemInsertion.lua, which only ever inserts GoM spawner items
-- into vanilla loot tables, never edits or removes vanilla entries. Treating
-- GoM as "incompatible with vanilla firearms" is a deliberate server design
-- choice (explicit request), enforced here for the two systems that hand
-- items directly to players (the shop and kit rewards) -- not a limitation
-- GoM itself imposes.
GoMCompat = GoMCompat or {}

-- Several well-known, unlikely-to-be-renamed GoM items rather than one, so a
-- single item getting renamed/removed in a future GoM update can't silently
-- disable detection. Same itemExists() pattern used everywhere else in this
-- mod (getScriptManager():FindItem(), pcall-guarded).
local PROBE_ITEMS = {
    "MarzGuns.M92FS", "MarzGuns.AK47", "MarzGuns.M4A1", "MarzGuns.9x19_Box",
}

local function itemExists(fullType)
    local ok, script = pcall(function() return getScriptManager():FindItem(fullType) end)
    return ok and script ~= nil
end

-- No internal caching on purpose: callers (Shop's validateCatalog(),
-- HardcoreKits' validateAll()) already only run this at boot and at their own
-- infrequent revalidation cadence, never in a per-frame/per-tick hot path.
-- Caching here would just add a second, easy-to-forget invalidation path on
-- top of those.
function GoMCompat.isActive()
    for _, fullType in ipairs(PROBE_ITEMS) do
        if itemExists(fullType) then return true end
    end
    return false
end

return GoMCompat
