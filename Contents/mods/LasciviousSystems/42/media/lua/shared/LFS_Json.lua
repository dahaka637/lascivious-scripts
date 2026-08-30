-- Lascivious Factions System - JSON codec (shared).
--
-- PZ exposes no JSON encoder/decoder to Lua. B42 parses JSON engine-side (translations
-- moved to language.json) but none of that is callable from a mod, so anything that
-- wants to read or write JSON has to bring its own.
--
-- Written here rather than vendoring one of the usual Lua libraries, for two reasons:
--
--  1. PZ's Kahlua sandbox is not stock Lua. It does not expose the `next` global (see
--     LFS_Shared.lua:17-20 -- calling it throws "Object tried to call nil"),
--     and the common rxi json.lua uses `next` in exactly the place a JSON encoder needs
--     it: deciding whether a table is empty. Every construct below is chosen to stay
--     inside what Kahlua actually provides, and emptiness goes through FF.isEmpty.
--  2. It avoids carrying a third-party licence for ~200 lines we would have had to audit
--     line by line anyway.
--
-- Pure data in, pure data out -- no IO, no world access, safe to require from any side.
--
-- Deliberate decisions worth knowing before you use it:
--
--  * `null` decodes to FF.Json.null, a unique sentinel, NOT to nil. Decoding to nil
--    would silently drop object keys and, far worse, renumber arrays -- a claim rect
--    list with a null in it would come back shorter rather than wrong-looking. Test with
--    `v == FF.Json.null`. Encoding the sentinel gives you `null` back.
--  * An empty Lua table encodes as `{}` (object), because Lua cannot distinguish an
--    empty list from an empty map. If you need `[]` specifically, pass FF.Json.EMPTY_ARRAY.
--  * Decoding enforces a depth limit. Content packs and registry snapshots are files a
--    server owner may have edited or downloaded, and unbounded recursion on a malformed
--    one would take the server down rather than report a bad file.

require "LFS_Shared"

local FF = LasciviousFactionsSystem
FF.Json = FF.Json or {}
local Json = FF.Json

-- Unique sentinels. Tables (not strings/numbers) so they can never collide with real
-- decoded content.
Json.null = setmetatable({}, { __tostring = function() return "null" end })
Json.EMPTY_ARRAY = setmetatable({}, { __tostring = function() return "[]" end })

local MAX_DEPTH = 64

-- ---------------------------------------------------------------------------
-- Encoding
-- ---------------------------------------------------------------------------

-- Characters JSON requires escaping, plus the two optional ones that make hand-edited
-- files behave (/ is left alone; escaping it is legal but noisy).
local ESCAPES = {
    ['"']  = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
}

local function escapeChar(ch)
    local mapped = ESCAPES[ch]
    if mapped then return mapped end
    -- Everything else below 0x20 is illegal raw in a JSON string and has no short form.
    return string.format("\\u%04x", string.byte(ch))
end

local function encodeString(s)
    return '"' .. string.gsub(s, '[%c"\\]', escapeChar) .. '"'
end

local function encodeNumber(n)
    -- NaN and the infinities have no JSON representation. Emitting them produces a file
    -- that no other parser will read, so fail loudly here instead.
    if n ~= n then error("json: cannot encode NaN") end
    if n == math.huge or n == -math.huge then error("json: cannot encode infinity") end
    -- %.14g keeps doubles round-trippable without printing 1 as "1.0".
    return string.format("%.14g", n)
end

-- Is `t` a dense 1..n array? Anything else -- string keys, holes, index 0 -- is an
-- object. Checked by counting rather than with `next`.
local function isArray(t)
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        if k % 1 ~= 0 or k < 1 then return false end
        count = count + 1
    end
    return count == #t
end

local encodeValue

local function encodeTable(t, indent, depth, out)
    if t == Json.null then out[#out + 1] = "null" return end
    if t == Json.EMPTY_ARRAY then out[#out + 1] = "[]" return end
    if depth > MAX_DEPTH then error("json: nesting too deep (cycle?)") end

    if FF.isEmpty(t) then out[#out + 1] = "{}" return end

    local pretty = indent ~= nil
    local pad, padEnd = "", ""
    if pretty then
        pad = "\n" .. string.rep(indent, depth + 1)
        padEnd = "\n" .. string.rep(indent, depth)
    end

    if isArray(t) then
        out[#out + 1] = "["
        for i = 1, #t do
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = pad
            encodeValue(t[i], indent, depth + 1, out)
        end
        out[#out + 1] = padEnd
        out[#out + 1] = "]"
        return
    end

    -- Objects: keys sorted, so a file written twice from equal data is byte-identical.
    -- That is what makes a snapshot diffable and a git-tracked content pack reviewable.
    local keys = {}
    for k in pairs(t) do
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" then
            error("json: object key must be a string or number, got " .. kt)
        end
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

    out[#out + 1] = "{"
    for i = 1, #keys do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = pad
        out[#out + 1] = encodeString(tostring(keys[i]))
        out[#out + 1] = pretty and ": " or ":"
        encodeValue(t[keys[i]], indent, depth + 1, out)
    end
    out[#out + 1] = padEnd
    out[#out + 1] = "}"
end

encodeValue = function(v, indent, depth, out)
    local t = type(v)
    if v == nil then out[#out + 1] = "null"
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "number" then out[#out + 1] = encodeNumber(v)
    elseif t == "string" then out[#out + 1] = encodeString(v)
    elseif t == "table" then encodeTable(v, indent, depth, out)
    else error("json: cannot encode a " .. t)
    end
end

-- Encode `value` to a JSON string. `opts.indent` (e.g. "  ") pretty-prints; omit it for
-- the compact form. Pretty-print anything a human is expected to open, and stay
-- compact for machine-only files.
-- Returns nil plus a message on failure rather than throwing, so a caller mid-tick
-- cannot be taken down by one bad field.
function Json.encode(value, opts)
    opts = opts or {}
    local out = {}
    local ok, err = pcall(encodeValue, value, opts.indent, 0, out)
    if not ok then return nil, tostring(err) end
    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Decoding
-- ---------------------------------------------------------------------------

local WHITESPACE = { [" "] = true, ["\t"] = true, ["\n"] = true, ["\r"] = true }

local DECODE_ESCAPES = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/',
    ['b'] = '\b', ['f'] = '\f', ['n'] = '\n', ['r'] = '\r', ['t'] = '\t',
}

-- Parser state is a plain table threaded through, rather than upvalues, so the decoder
-- is reentrant -- the probe decodes while encoding in the same tick.
local function skipWhitespace(st)
    local s, i = st.s, st.i
    while i <= #s and WHITESPACE[string.sub(s, i, i)] do i = i + 1 end
    st.i = i
end

local function fail(st, msg)
    error(string.format("json: %s at position %d", msg, st.i), 0)
end

-- One Unicode codepoint to UTF-8 bytes. string.char is byte-wise in Lua 5.1/Kahlua, so
-- the encoding is done by hand.
local function utf8Encode(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
    end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000),
                           0x80 + (math.floor(cp / 0x40) % 0x40),
                           0x80 + (cp % 0x40))
    end
    return string.char(0xF0 + math.floor(cp / 0x40000),
                       0x80 + (math.floor(cp / 0x1000) % 0x40),
                       0x80 + (math.floor(cp / 0x40) % 0x40),
                       0x80 + (cp % 0x40))
end

local function parseHex4(st)
    local hex = string.sub(st.s, st.i, st.i + 3)
    if #hex < 4 or string.find(hex, "[^0-9A-Fa-f]") then fail(st, "bad \\u escape") end
    st.i = st.i + 4
    return tonumber(hex, 16)
end

local function parseString(st)
    st.i = st.i + 1        -- opening quote
    local parts = {}
    local s = st.s
    while true do
        if st.i > #s then fail(st, "unterminated string") end
        local ch = string.sub(s, st.i, st.i)
        if ch == '"' then
            st.i = st.i + 1
            return table.concat(parts)
        elseif ch == '\\' then
            st.i = st.i + 1
            local esc = string.sub(s, st.i, st.i)
            local simple = DECODE_ESCAPES[esc]
            if simple then
                parts[#parts + 1] = simple
                st.i = st.i + 1
            elseif esc == 'u' then
                st.i = st.i + 1
                local cp = parseHex4(st)
                -- Surrogate pair: a high surrogate must be followed by \uDC00-\uDFFF, and
                -- the two combine into one codepoint above the BMP.
                if cp >= 0xD800 and cp <= 0xDBFF then
                    if string.sub(s, st.i, st.i + 1) ~= "\\u" then fail(st, "lone surrogate") end
                    st.i = st.i + 2
                    local lo = parseHex4(st)
                    if lo < 0xDC00 or lo > 0xDFFF then fail(st, "bad low surrogate") end
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                end
                parts[#parts + 1] = utf8Encode(cp)
            else
                fail(st, "invalid escape \\" .. esc)
            end
        else
            parts[#parts + 1] = ch
            st.i = st.i + 1
        end
    end
end

local function parseNumber(st)
    local start = st.i
    local finish = string.find(st.s, "[^0-9eE%+%-%.]", st.i)
    finish = (finish and finish - 1) or #st.s
    local text = string.sub(st.s, start, finish)
    local n = tonumber(text)
    if not n then fail(st, "bad number '" .. text .. "'") end
    st.i = finish + 1
    return n
end

local function parseLiteral(st, word, value)
    if string.sub(st.s, st.i, st.i + #word - 1) ~= word then
        fail(st, "unexpected character")
    end
    st.i = st.i + #word
    return value
end

local parseValue

local function parseArray(st, depth)
    st.i = st.i + 1        -- [
    local arr = {}
    skipWhitespace(st)
    if string.sub(st.s, st.i, st.i) == "]" then st.i = st.i + 1 return arr end
    while true do
        arr[#arr + 1] = parseValue(st, depth + 1)
        skipWhitespace(st)
        local ch = string.sub(st.s, st.i, st.i)
        st.i = st.i + 1
        if ch == "]" then return arr end
        if ch ~= "," then fail(st, "expected ',' or ']'") end
        skipWhitespace(st)
    end
end

local function parseObject(st, depth)
    st.i = st.i + 1        -- {
    local obj = {}
    skipWhitespace(st)
    if string.sub(st.s, st.i, st.i) == "}" then st.i = st.i + 1 return obj end
    while true do
        skipWhitespace(st)
        if string.sub(st.s, st.i, st.i) ~= '"' then fail(st, "expected a key string") end
        local key = parseString(st)
        skipWhitespace(st)
        if string.sub(st.s, st.i, st.i) ~= ":" then fail(st, "expected ':'") end
        st.i = st.i + 1
        obj[key] = parseValue(st, depth + 1)
        skipWhitespace(st)
        local ch = string.sub(st.s, st.i, st.i)
        st.i = st.i + 1
        if ch == "}" then return obj end
        if ch ~= "," then fail(st, "expected ',' or '}'") end
    end
end

parseValue = function(st, depth)
    if depth > MAX_DEPTH then fail(st, "nesting too deep") end
    skipWhitespace(st)
    if st.i > #st.s then fail(st, "unexpected end of input") end
    local ch = string.sub(st.s, st.i, st.i)
    if ch == '"' then return parseString(st) end
    if ch == "{" then return parseObject(st, depth) end
    if ch == "[" then return parseArray(st, depth) end
    if ch == "t" then return parseLiteral(st, "true", true) end
    if ch == "f" then return parseLiteral(st, "false", false) end
    if ch == "n" then return parseLiteral(st, "null", Json.null) end
    if string.find(ch, "[%d%-]") then return parseNumber(st) end
    fail(st, "unexpected character '" .. ch .. "'")
end

-- Decode a JSON string. Returns the value, or nil plus a message -- every caller here is
-- reading a file that a server owner may have hand-edited, so a parse failure is an
-- ordinary outcome to report, not an error to propagate into the tick.
function Json.decode(text)
    if type(text) ~= "string" then return nil, "json: expected a string" end
    local st = { s = text, i = 1 }
    local ok, result = pcall(parseValue, st, 0)
    if not ok then return nil, tostring(result) end
    skipWhitespace(st)
    if st.i <= #st.s then
        return nil, string.format("json: trailing content at position %d", st.i)
    end
    return result
end

FF.checkpoint("json codec loaded")
