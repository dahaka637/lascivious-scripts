-- Log administrativo legivel (secao 25). Diferente do Aegis, nao precisamos
-- listar/ler esses logs de dentro do jogo (nao ha visualizador in-game na
-- v1), entao dispensamos o esquema de manifest deles: um arquivo texto por
-- dia, so anexado, que qualquer admin consegue abrir direto no disco.
if isClient() then return end

require "HardcoreKits_Config"
require "HardcoreKits_Utils"
require "HardcoreKits_Identity"

HardcoreKitsAudit = HardcoreKitsAudit or {}

local ROOT = "HardcoreKits"

local function pathOk(relPath)
    if type(relPath) ~= "string" or relPath == "" then return false end
    if relPath:find("%.%.") then return false end
    if relPath:find("|") or relPath:find("\\") then return false end
    if relPath:sub(1, #ROOT + 1) ~= ROOT .. "/" then return false end
    return true
end

local function dateShort(epoch)
    local ok, t = pcall(function() return os.date("*t", epoch) end)
    if ok and type(t) == "table" and t.year and t.year > 2000 then
        return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
    end
    return "day" .. tostring(math.floor(epoch / 86400))
end

local function timeReadable(epoch)
    local ok, t = pcall(function() return os.date("*t", epoch) end)
    if ok and type(t) == "table" and t.year then
        return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
    end
    return tostring(epoch)
end

local reportedError = false
local function appendLine(line)
    local now = HardcoreKitsUtils.realTime()
    local path = ROOT .. "/Audit/" .. dateShort(now) .. ".txt"
    if not pathOk(path) then return end
    local w = nil
    local ok, err = pcall(function()
        w = getFileWriter(path, true, true)
        if not w then error("getFileWriter retornou nil") end
        w:writeln(line)
    end)
    if w then pcall(function() w:close() end) end
    if not ok and not reportedError then
        reportedError = true
        print("[HardcoreKits] Falha ao escrever log de auditoria: " .. tostring(err))
    end
end

local FIELD_ORDER = {
    "ClaimId", "Player", "SteamID", "Character", "Type", "Status", "Reason",
    "HoursSurvived", "Food", "Drink", "Resource", "MedicalKit", "Melee", "Firearm", "Ammo", "Magazine", "Backpack", "Skills",
    "Resources", "Granted", "Total",
}

-- uma linha chave=valor por tentativa/resgate -- facil de grep, sem depender
-- de nenhum parser
function HardcoreKitsAudit.log(fields)
    if HardcoreKitsConfig.EnableAuditLog ~= true then return end
    local now = HardcoreKitsUtils.realTime()
    local parts = { "[" .. timeReadable(now) .. "]" }
    for _, key in ipairs(FIELD_ORDER) do
        if fields[key] ~= nil then
            local value = tostring(fields[key]):gsub("[\r\n\t]", " ")
            table.insert(parts, key .. "=" .. value)
        end
    end
    appendLine(table.concat(parts, " "))
end

local function fmtSlot(entry)
    if not entry then return nil end
    if not entry.item then return "none" end
    return string.format("%s x%s%s", tostring(entry.item), tostring(entry.qty or 1), entry.ok and "" or "(FALHOU)")
end

-- agrupa por slot em LISTAS, nao numa entrada so -- comida/bebida podem ter
-- varias entradas no mesmo slot em FoodDrinkMultiRollMode, e sobrescrever
-- perderia todas menos a ultima no log de auditoria
local function fmtSlotList(bySlot, slot)
    local list = bySlot[slot]
    if not list or #list == 0 then return nil end
    local parts = {}
    for _, e in ipairs(list) do table.insert(parts, fmtSlot(e)) end
    return table.concat(parts, "; ")
end

function HardcoreKitsAudit.logInitialClaim(player, accountId, tx, result, status, reason)
    local by = {}
    for _, e in ipairs((result and result.log) or {}) do
        by[e.slot] = by[e.slot] or {}
        table.insert(by[e.slot], e)
    end
    HardcoreKitsAudit.log({
        ClaimId = tx and tx.claimId,
        Player = HardcoreKitsIdentity.username(player),
        SteamID = accountId,
        Character = HardcoreKitsIdentity.characterName(player),
        Type = "Initial",
        Status = status,
        Reason = reason,
        Food = fmtSlotList(by, "food"),
        Drink = fmtSlotList(by, "drink"),
        Resource = fmtSlotList(by, "resource"),
        MedicalKit = fmtSlotList(by, "resource:medicalkit"),
        Melee = fmtSlotList(by, "melee"),
        Firearm = fmtSlotList(by, "firearm") or "None",
        Ammo = fmtSlotList(by, "ammo"),
        Magazine = fmtSlotList(by, "magazine"),
        Backpack = fmtSlotList(by, "backpack"),
        Skills = fmtSlotList(by, "skill"),
        Granted = result and result.granted,
        Total = result and result.total,
    })
end

function HardcoreKitsAudit.logSurvivalClaim(player, accountId, tx, result, status, reason)
    local resources = {}
    for _, e in ipairs((result and result.log) or {}) do
        table.insert(resources, string.format("%s:%s", e.slot, fmtSlot(e)))
    end
    HardcoreKitsAudit.log({
        ClaimId = tx and tx.claimId,
        Player = HardcoreKitsIdentity.username(player),
        SteamID = accountId,
        Character = HardcoreKitsIdentity.characterName(player),
        Type = "Survival",
        Status = status,
        Reason = reason,
        HoursSurvived = HardcoreKitsIdentity.hoursSurvived(player),
        Resources = table.concat(resources, "; "),
        Granted = result and result.granted,
        Total = result and result.total,
    })
end

function HardcoreKitsAudit.logAttemptDenied(player, accountId, claimType, reason)
    HardcoreKitsAudit.log({
        Player = HardcoreKitsIdentity.username(player),
        SteamID = accountId,
        Character = HardcoreKitsIdentity.characterName(player),
        Type = claimType,
        Status = "denied",
        Reason = reason,
    })
end
