CHBConfig = {}
CHBConfig.VERSION = "1.0"
CHBConfig.configCache = nil
CHBConfig.configValidated = false
CHBConfig.CONFIG_FILE = "CleanHotbarConfig.txt"
CHBConfig.LEGACY_CONFIG_FILE = "CleanHotbarConfig.lua"

-- ----------------------------------------- --
-- serializeTable
-- ----------------------------------------- --
function CHBConfig.serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep("    ", depth)

    if name then
        tmp = tmp .. name .. " = "
    end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp = tmp .. CHBConfig.serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep("    ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[" .. type(val) .. "]\""
    end

    return tmp
end

function CHBConfig.readConfigFile(fileName)
    local ok, file = pcall(getFileReader, fileName, false)
    if not ok or file == nil then
        return nil
    end

    local content = ""
    local line = file:readLine()
    while line do
        content = content .. line .. "\n"
        line = file:readLine()
    end
    file:close()

    if content == "" then
        return nil
    end

    -- Build 42.20 does not expose loadstring. Older versions executed the
    -- serialized table here, which now raises on every boot. Parse only the
    -- fixed Clean HotBar schema instead; this reads both the current .txt and
    -- the legacy .lua file without executing their contents.
    local nestedKeys = {
        showItemDurability = true,
        showWeaponHeadCondition = true,
        showWeaponSharpness = true,
        showWeaponAmmo = true,
        showItemTooltip = true,
    }
    local scalarTypes = {
        version = "string",
        statusBarHeightScale = "number",
        ammoTextScale = "number",
        hotbarScale = "number",
        showWeaponDurabilityAlert = "boolean",
        showEmptySlots = "boolean",
        hotbarOpacity = "number",
    }

    local function valueOf(raw, expected)
        if expected == "boolean" then
            if raw == "true" then return true end
            if raw == "false" then return false end
        elseif expected == "number" then
            return tonumber(raw)
        elseif expected == "string" then
            local value = raw:match('^"(.*)"$') or raw:match("^'(.*)'$")
            if value then
                value = value:gsub('\\"', '"'):gsub("\\'", "'"):gsub("\\\\", "\\")
                return value
            end
        end
        return nil
    end

    local config = {}
    local section = nil
    local found = false
    for lineText in content:gmatch("[^\r\n]+") do
        local opened = lineText:match("^%s*([%w_]+)%s*=%s*{%s*,?%s*$")
        if opened and nestedKeys[opened] then
            section = opened
            config[section] = config[section] or {}
        elseif lineText:match("^%s*}%s*,?%s*$") then
            section = nil
        else
            local key, raw = lineText:match("^%s*([%w_]+)%s*=%s*(.-)%s*,?%s*$")
            if key and raw then
                if section and (key == "hotbar" or key == "equipitem") then
                    local value = valueOf(raw, "boolean")
                    if value ~= nil then
                        config[section][key] = value
                        found = true
                    end
                elseif not section and scalarTypes[key] then
                    local value = valueOf(raw, scalarTypes[key])
                    if value ~= nil then
                        config[key] = value
                        found = true
                    end
                end
            end
        end
    end

    return found and config or nil
end

function CHBConfig.saveConfig(config)
    -- Keep the in-session cache updated even if disk writing fails.
    CHBConfig.configCache = config

    local ok, file = pcall(getFileWriter, CHBConfig.CONFIG_FILE, true, false)
    if not ok or file == nil then
        return nil
    end

    local contents = "return " .. CHBConfig.serializeTable(config)
    local success, errorMsg = pcall(function()
        file:write(contents)
        file:close()
    end)

    if not success then
        print("CleanHotbar: Error saving config to " .. tostring(CHBConfig.CONFIG_FILE) .. " - " .. tostring(errorMsg))
        return nil
    end

    return true
end

function CHBConfig.loadConfig()
    if CHBConfig.configCache then
        return CHBConfig.configCache
    end

    local config = CHBConfig.readConfigFile(CHBConfig.CONFIG_FILE)
    if config then
        CHBConfig.configCache = config
        CHBConfig.configValidated = false
        return config
    end

    -- Build 42.20+ no longer allows writing .lua config files through getFileWriter,
    -- but older Clean HotBar versions used CleanHotbarConfig.lua. Keep reading it
    -- so existing settings can be migrated to CleanHotbarConfig.txt automatically.
    config = CHBConfig.readConfigFile(CHBConfig.LEGACY_CONFIG_FILE)
    if config then
        CHBConfig.configCache = config
        CHBConfig.configValidated = false
        CHBConfig.saveConfig(config)
        return config
    end

    return nil
end

-- ----------------------------------------- --
-- Config Manager
-- ----------------------------------------- --
function CHBConfig.getDefaultConfig()
    return {
        version = CHBConfig.VERSION,
        showItemDurability = { hotbar = true, equipitem = true },
        showWeaponHeadCondition = { hotbar = true, equipitem = true },
        showWeaponSharpness = { hotbar = true, equipitem = true },
        showWeaponAmmo = { hotbar = true, equipitem = true },
        showItemTooltip = { hotbar = false, equipitem = false },
        statusBarHeightScale = 1.0,
        ammoTextScale = 0.8,
        hotbarScale = 1.0,
        showWeaponDurabilityAlert = true,
        showEmptySlots = true,
        hotbarOpacity = 0.6,
    }
end

function CHBConfig.getConfig()
    -- Configuration validation only needs to run after loading or migration.
    -- The hotbar asks for its config every frame, so returning the validated
    -- in-session table directly avoids repeatedly rebuilding defaults and walking it.
    if CHBConfig.configCache and CHBConfig.configValidated then
        return CHBConfig.configCache
    end

    local config = CHBConfig.loadConfig()

    if not config then
        config = CHBConfig.getDefaultConfig()
        CHBConfig.configCache = config
        CHBConfig.configValidated = true
        CHBConfig.saveConfig(config)
        return config
    end

    local defaults = CHBConfig.getDefaultConfig()
    local needsSave = false

    for key, defaultValue in pairs(defaults) do
        if config[key] == nil then
            config[key] = defaultValue
            needsSave = true
        else
            local configType = type(config[key])
            local defaultType = type(defaultValue)

            if configType ~= defaultType then
                config[key] = defaultValue
                needsSave = true
            end
        end
    end

    CHBConfig.configCache = config
    CHBConfig.configValidated = true

    if needsSave then
        CHBConfig.saveConfig(config)
    end

    return config
end

function CHBConfig.updateConfig(key, value, subKey)
    local config = CHBConfig.getConfig()

    if subKey then
        if not config[key] then
            config[key] = {}
        end
        config[key][subKey] = value
    else
        config[key] = value
    end

    CHBConfig.configCache = config
    CHBConfig.configValidated = true
    CHBConfig.saveConfig(config)
end

Events.OnGameBoot.Add(CHBConfig.getConfig)

return CHBConfig
