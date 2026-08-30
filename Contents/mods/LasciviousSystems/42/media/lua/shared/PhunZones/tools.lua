local luautils = luautils
local loadstring = loadstring
local tools = {}

tools.isLocal = not isClient() and not isServer() and not isCoopHost()

function tools.debug(...)

    local args = {...}
    for i, v in ipairs(args) do
        if type(v) == "table" then
            tools.printTable(v)
        else
            print(tostring(v))
        end
    end

end

function tools.printTable(t, indent, seen)
    indent = indent or ""
    if type(t) ~= "table" then print(indent .. tostring(t)); return end
    seen = seen or {}
    if seen[t] then print(indent .. "<cycle>"); return end
    seen[t] = true
    for key, value in pairs(t or {}) do
        if type(value) == "table" then
            print(indent .. tostring(key) .. ":")
            tools.printTable(value, indent .. "  ", seen)
        elseif type(value) ~= "function" then
            print(indent .. tostring(key) .. ": " .. tostring(value))
        end
    end
    seen[t] = nil
end

function tools.getPlayerByUsername(name, caseSensitive)
    if type(name) ~= "string" or name == "" then return nil end
    local online = tools.onlinePlayers()
    if not online then return nil end
    local text = caseSensitive and name or name:lower()
    for i = 0, online:size() - 1 do
        local player = online:get(i)
        local ok, username = pcall(function() return player and player:getUsername() end)
        if ok and type(username) == "string" and ((caseSensitive and username == name) or
            (not caseSensitive and username:lower() == text)) then
            return player
        end
    end
    return nil
end

function tools.onlinePlayers(all)

    local onlinePlayers;

    if tools.isLocal then
        onlinePlayers = ArrayList.new();
        local p = getPlayer()
        if p then onlinePlayers:add(p) end
    elseif all ~= false and isClient() then
        onlinePlayers = ArrayList.new();
        for i = 0, getOnlinePlayers():size() - 1 do
            local player = getOnlinePlayers():get(i);
            if player:isLocalPlayer() then
                onlinePlayers:add(player);
            end
        end
    else
        onlinePlayers = getOnlinePlayers() or ArrayList.new();
    end

    return onlinePlayers;
end

function tools.isAdmin()

    return (getAccessLevel and (getAccessLevel() == "moderator" or getAccessLevel() == "admin")) or false

end

-- ---------------------------------------------------------------------------
-- SHALLOW COPY
-- Returns a shallow copy of a table, optionally excluding specified keys.
-- Nested tables are not copied — they remain as shared references.
--
-- @param original    table
-- @param excludeKeys table|nil  array of keys to omit  e.g. {"points", "inherits"}
-- @return            table
-- ---------------------------------------------------------------------------
function tools.shallowCopy(original, excludeKeys)
    local exclude = {}
    for _, k in ipairs(excludeKeys or {}) do
        exclude[k] = true
    end
    local copy = {}
    for key, value in pairs(type(original) == "table" and original or {}) do
        if not exclude[key] then
            copy[key] = value
        end
    end
    return copy
end

-- ---------------------------------------------------------------------------
-- DEEP COPY
-- Returns a fully independent deep copy of a table, optionally excluding
-- specified keys. Metatables are copied as-is (shallow reference).
-- Safe for nested zone property tables.
--
-- @param original    table
-- @param excludeKeys table|nil  array of keys to omit
-- @return            table
-- ---------------------------------------------------------------------------
function tools.deepCopy(original, excludeKeys)
    local exclude = {}
    for _, k in ipairs(excludeKeys or {}) do
        exclude[k] = true
    end

    local seen = {}
    local function _copy(obj)
        if type(obj) ~= "table" then
            return obj
        end
        if seen[obj] then return seen[obj] end
        local result = {}
        seen[obj] = result
        for k, v in pairs(obj) do
            if not exclude[k] then
                result[_copy(k)] = _copy(v)
            end
        end
        setmetatable(result, getmetatable(obj))
        return result
    end

    return _copy(original)
end

-- ---------------------------------------------------------------------------
-- TABLE SERIALISATION
-- Converts a Lua table to a formatted string representation suitable for
-- writing to a file and reloading with loadstring.
-- Handles nested tables, strings, booleans, and numbers.
-- Array parts are serialised before non-array (hash) parts.
-- ---------------------------------------------------------------------------
local LUA_RESERVED = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
    ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true,
    ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true,
    ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true
}

-- Aceita somente o subconjunto literal emitido por tableToString(). O arquivo
-- de configuracao historicamente e Lua (`return { ... }`), portanto trocar o
-- formato quebraria saves existentes; esta varredura preserva o formato sem
-- permitir que loadstring execute chamadas, funcoes, loops ou operadores.
function tools.safeLiteralSource(src)
    if type(src) ~= "string" then return false, "source is not text" end
    local stripped = src:match("^%s*(.-)%s*$")
    if not stripped:match("^return%s*{") then
        return false, "source must start with 'return { ... }'"
    end

    local len, i, nesting = #stripped, 1, 0
    local function skipSpace(pos)
        while pos <= len and stripped:sub(pos, pos):match("%s") do pos = pos + 1 end
        return pos
    end
    local function previousNonSpace(pos)
        pos = pos - 1
        while pos >= 1 and stripped:sub(pos, pos):match("%s") do pos = pos - 1 end
        return pos >= 1 and stripped:sub(pos, pos) or nil
    end

    while i <= len do
        local ch = stripped:sub(i, i)
        if ch:match("%s") then
            i = i + 1
        elseif ch == "\"" or ch == "'" then
            local quote, closed = ch, false
            i = i + 1
            while i <= len do
                local current = stripped:sub(i, i)
                if current == "\\" then
                    i = i + 2
                elseif current == quote then
                    i = i + 1
                    closed = true
                    break
                else
                    i = i + 1
                end
            end
            if not closed then return false, "unterminated string literal" end
        elseif ch == "-" and stripped:sub(i + 1, i + 1) == "-" then
            -- Comentarios de linha sao inertes. Long comments sao rejeitados
            -- para manter o reconhecedor pequeno e sem ambiguidades.
            if stripped:sub(i + 2, i + 3) == "[[" then
                return false, "long comments are not allowed"
            end
            local newline = stripped:find("\n", i + 2, true)
            i = newline and (newline + 1) or (len + 1)
        elseif ch:match("[%a_]") then
            local start = i
            i = i + 1
            while i <= len and stripped:sub(i, i):match("[%w_]") do i = i + 1 end
            local word = stripped:sub(start, i - 1)
            if word == "return" then
                if start ~= 1 then return false, "only one leading return is allowed" end
            elseif word ~= "true" and word ~= "false" and word ~= "nil" then
                local after = skipSpace(i)
                if stripped:sub(after, after) ~= "=" or stripped:sub(after + 1, after + 1) == "=" then
                    return false, "executable identifier is not allowed: " .. word
                end
            end
        elseif ch:match("%d") or (ch == "." and stripped:sub(i + 1, i + 1):match("%d")) then
            local rest = stripped:sub(i)
            local numberToken = rest:match("^%d+%.?%d*[eE][%+%-]?%d+")
                or rest:match("^%.%d+[eE][%+%-]?%d+")
                or rest:match("^%d+%.?%d*") or rest:match("^%.%d+")
            if not numberToken then return false, "invalid number literal" end
            i = i + #numberToken
        elseif ch == "+" or ch == "-" then
            local prev = previousNonSpace(i)
            local nextCh = stripped:sub(i + 1, i + 1)
            if not nextCh:match("[%d%.]") or (prev ~= "=" and prev ~= "{" and prev ~= "["
                and prev ~= "," and prev ~= ";") then
                return false, "operators are not allowed"
            end
            i = i + 1
        elseif ch == "{" or ch == "[" then
            nesting = nesting + 1
            if nesting > 64 then return false, "literal is nested too deeply" end
            i = i + 1
        elseif ch == "}" or ch == "]" then
            nesting = nesting - 1
            if nesting < 0 then return false, "unbalanced literal delimiters" end
            i = i + 1
        elseif ch == "," or ch == ";" then
            i = i + 1
        elseif ch == "=" and stripped:sub(i + 1, i + 1) ~= "=" then
            i = i + 1
        else
            return false, "executable token is not allowed near byte " .. tostring(i)
        end
    end
    if nesting ~= 0 then return false, "unbalanced literal delimiters" end
    return true
end

local function validateLoadedLiteral(value, depth, seen, stats)
    stats.nodes = stats.nodes + 1
    if stats.nodes > 100000 then return false, "too many values" end
    local kind = type(value)
    if kind == "number" then
        return value == value and value ~= math.huge and value ~= -math.huge,
            "non-finite number"
    elseif kind == "string" then
        return #value <= 4096, "oversized string"
    elseif kind == "boolean" or kind == "nil" then
        return true
    elseif kind ~= "table" then
        return false, "unsupported value type " .. kind
    end
    if depth > 64 then return false, "table is nested too deeply" end
    if seen[value] then return false, "cyclic/shared table reference" end
    seen[value] = true
    for key, child in pairs(value) do
        local keyKind = type(key)
        if keyKind ~= "string" and keyKind ~= "number" and keyKind ~= "boolean" then
            seen[value] = nil
            return false, "unsupported key type " .. keyKind
        end
        if keyKind == "number" and (key ~= key or key == math.huge or key == -math.huge) then
            seen[value] = nil
            return false, "non-finite numeric key"
        end
        local ok, err = validateLoadedLiteral(child, depth + 1, seen, stats)
        if not ok then seen[value] = nil; return false, err end
    end
    seen[value] = nil
    return true
end

local function serializedScalar(value)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        return tostring(value)
    end
    error("unsupported/non-finite value of type " .. kind)
end

function tools.tableToString(tbl, indent, seen)
    if type(tbl) ~= "table" then error("table expected") end
    indent = tonumber(indent) or 0
    if indent < 0 or indent > 64 then error("invalid table depth") end
    seen = seen or {}
    if seen[tbl] then error("cyclic/shared table reference") end
    seen[tbl] = true
    local prefix = string.rep("  ", indent + 1)
    local result = {}
    local doneKeys = {}

    -- Array part first (sequential numeric keys from 1)
    for i = 1, #tbl do
        local value = tbl[i]
        doneKeys[i] = true
        local line
        if type(value) == "table" then
            line = prefix .. tools.tableToString(value, indent + 1, seen)
        else
            line = prefix .. serializedScalar(value)
        end
        table.insert(result, line)
    end

    -- Non-array (hash) part
    for key, value in pairs(tbl) do
        if not doneKeys[key] then
            local keyStr
            if type(key) == "string" then
                -- Bare key if valid identifier, bracketed+quoted otherwise
                if string.match(key, "^[%a_][%w_]*$") and not LUA_RESERVED[key] then
                    keyStr = key .. " = "
                else
                    keyStr = string.format("[%q] = ", key)
                end
            elseif type(key) == "number" or type(key) == "boolean" then
                keyStr = "[" .. serializedScalar(key) .. "] = "
            else
                error("unsupported table key type " .. type(key))
            end

            local line
            if type(value) == "table" then
                line = prefix .. keyStr .. tools.tableToString(value, indent + 1, seen)
            else
                line = prefix .. keyStr .. serializedScalar(value)
            end
            table.insert(result, line)
        end
    end

    seen[tbl] = nil
    return "{\n" .. table.concat(result, ",\n") .. "\n" .. string.rep("  ", indent) .. "}"
end

-- ---------------------------------------------------------------------------
-- SAVE TABLE
-- Serialises a table and writes it to a file in the server Lua folder.
-- The file is written as a valid Lua module (return { ... }) so it can be
-- loaded directly with loadTable or require.
--
-- @param filename  string  path relative to the server Lua folder
-- @param data      table   the table to serialise and save
-- ---------------------------------------------------------------------------
function tools.saveTable(filename, data)
    if type(filename) ~= "string" or filename == "" or filename:find("..", 1, true)
        or filename:find("\\", 1, true) or type(data) ~= "table" then return false end
    local fileWriterObj = nil
    local ok, err = pcall(function()
        fileWriterObj = getFileWriter(filename, true, false)
        if not fileWriterObj then error("getFileWriter returned nil") end
        fileWriterObj:write("return " .. tools.tableToString(data))
    end)
    if fileWriterObj then pcall(function() fileWriterObj:close() end) end
    if not ok then
        print("PhunZones file_utils: error saving '" .. filename .. "': " .. tostring(err))
        return false
    end
    return true
end

-- ---------------------------------------------------------------------------
-- TABLE OF STRINGS TO TABLE
-- Internal helper. Takes an array of strings (lines read from a file),
-- concatenates them, and executes the result as a Lua chunk to produce
-- a table. Handles files that do or do not start with "return".
--
-- @param lines  table<string>  array of file lines
-- @return       table|nil, string|nil  (result, error message)
-- ---------------------------------------------------------------------------
local function tableOfStringsToTable(lines)
    if not lines or type(lines) ~= "table" or #lines == 0 then
        return nil, "invalid input: empty or non-table"
    end

    local startsWithReturn = luautils.stringStarts(lines[1], "return")
    local src
    if startsWithReturn then
        src = table.concat(lines, "\n")
    else
        src = "return {\n" .. table.concat(lines, "\n") .. "\n}"
    end

    local safe, safeErr = tools.safeLiteralSource(src)
    if not safe then return nil, "unsafe literal: " .. tostring(safeErr) end

    local ok, chunk, compileErr = pcall(loadstring, src)
    if not ok or type(chunk) ~= "function" then
        return nil, "loadstring error: " .. tostring(compileErr or chunk)
    end

    -- Kahlua/Lua 5.1: mesmo com a whitelist acima, remova o ambiente global
    -- como defesa em profundidade caso a gramatica seja ampliada no futuro.
    if setfenv then
        local envOk, envErr = pcall(setfenv, chunk, {})
        if not envOk then return nil, "sandbox error: " .. tostring(envErr) end
    end

    local ok2, result = pcall(chunk)
    if not ok2 then
        return nil, "execution error: " .. tostring(result)
    end

    if type(result) ~= "table" then return nil, "loaded value is not a table" end
    local valid, validationErr = validateLoadedLiteral(result, 1, {}, { nodes = 0 })
    if not valid then return nil, "invalid literal table: " .. tostring(validationErr) end
    return result, nil
end

-- ---------------------------------------------------------------------------
-- LOAD TABLE
-- Reads a Lua file from the server Lua folder and returns its contents as
-- a table. Returns nil if the file does not exist or cannot be parsed.
--
-- Unlike require, this bypasses Lua's module cache so it always reflects
-- the current state of the file on disk. Use this for mutable config files.
-- Use require for static data files that never change at runtime.
--
-- @param filename          string   path relative to the server Lua folder
-- @param createIfNotExists boolean  if true, creates the file if missing
-- @return                  table|nil
-- ---------------------------------------------------------------------------
function tools.loadTable(filename, createIfNotExists)
    if type(filename) ~= "string" or filename == "" or filename:find("..", 1, true)
        or filename:find("\\", 1, true) then return nil end
    local fileReaderObj = getFileReader(filename, createIfNotExists == true)
    if not fileReaderObj then
        return nil
    end

    local lines, totalBytes = {}, 0
    local okRead, readErr = pcall(function()
        local line = fileReaderObj:readLine()
        while line do
            totalBytes = totalBytes + #line + 1
            if totalBytes > 1024 * 1024 or #lines >= 25000 then error("file too large") end
            lines[#lines + 1] = line
            line = fileReaderObj:readLine()
        end
    end)
    pcall(function() fileReaderObj:close() end)
    if not okRead then
        print("PhunZones file_utils: error reading '" .. tostring(filename) .. "': " .. tostring(readErr))
        return nil
    end

    -- Guard against empty files
    if #lines == 0 then
        return nil
    end

    -- Strip trailing comma from last line (defensive: handles hand-edited files)
    if lines[#lines]:sub(-1) == "," then
        lines[#lines] = lines[#lines]:sub(1, -2)
    end

    local result, err = tableOfStringsToTable(lines)
    if err then
        print("PhunZones file_utils: error loading '" .. filename .. "': " .. err)
        return nil
    end

    return result
end

return tools
