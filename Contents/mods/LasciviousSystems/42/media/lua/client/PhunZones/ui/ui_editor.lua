-- ui_editor.lua
-- Standalone data editor window for PhunZones export / import.
-- Provides a multiline text editor for the custom ModData layer,
-- allowing copy/paste sharing and direct Lua editing.
if isServer() then
    return
end

local Core = PhunZones

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6

local profileName = "PhunZonesConfigEditor"
Core.ui.configEditor = ISCollapsableWindowJoypad:derive(profileName)
Core.ui.configEditor.instances = {}
local UI = Core.ui.configEditor

-- ===========================================================================
-- SERIALISATION / VALIDATION
-- ===========================================================================

local IMPORT_MAX_BYTES = 64 * 1024
local IMPORT_MAX_DEPTH = 12
local IMPORT_MAX_NODES = 20000
local IMPORT_MAX_ZONES = 128
local IMPORT_MAX_FIELDS = 64
local IMPORT_MAX_POINTS = 256
local IMPORT_MAX_COORD = 1000000
local IMPORT_MAX_CHUNK_CELLS = 100000
local CHUNK_SIZE = 300

local function finiteNumber(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

-- loadstring nao oferece limite de instrucoes no Kahlua. Antes de compilar,
-- restringe a entrada ao subconjunto produzido por tableToString: um unico
-- `return` seguido apenas de construtores de tabela e valores literais. Isso
-- elimina loops, funcoes e chamadas sem depender de debug.sethook.
local function safeLiteralSource(src)
    if not Core.tools or type(Core.tools.safeLiteralSource) ~= "function" then
        return false, "Safe literal parser is unavailable"
    end
    return Core.tools.safeLiteralSource(src)
end

local function validateSerializable(value, path, depth, seen, stats)
    local kind = type(value)
    stats.nodes = stats.nodes + 1
    if stats.nodes > IMPORT_MAX_NODES then return false, "Import contains too many values" end
    if kind == "number" then
        if not finiteNumber(value) then return false, path .. " contains a non-finite number" end
        return true
    elseif kind == "string" then
        if #value > 1024 then return false, path .. " contains an oversized string" end
        return true
    elseif kind == "boolean" or kind == "nil" then
        return true
    elseif kind ~= "table" then
        return false, path .. " contains unsupported type " .. kind
    end
    if depth > IMPORT_MAX_DEPTH then return false, path .. " is nested too deeply" end
    if seen[value] then return false, path .. " contains a cycle/shared table reference" end
    seen[value] = true
    for key, child in pairs(value) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then
            seen[value] = nil
            return false, path .. " has unsupported key type " .. keyType
        end
        if keyType == "number" and not finiteNumber(key) then
            seen[value] = nil
            return false, path .. " has a non-finite numeric key"
        end
        if keyType == "string" and #key > 256 then
            seen[value] = nil
            return false, path .. " has an oversized key"
        end
        local ok, err = validateSerializable(child, path .. "." .. tostring(key), depth + 1, seen, stats)
        if not ok then seen[value] = nil; return false, err end
    end
    seen[value] = nil
    return true
end

function UI:buildExportString()
    local md = ModData.getOrCreate(Core.const.modifiedModData)
    return "return " .. Core.tools.tableToString(md) .. "\n"
end

function UI:parseImportString(src)
    if type(src) ~= "string" then return nil, "Import must be text" end
    if #src == 0 or #src > IMPORT_MAX_BYTES then
        return nil, "Import size must be between 1 and " .. tostring(IMPORT_MAX_BYTES) .. " bytes"
    end
    local safe, safeErr = safeLiteralSource(src)
    if not safe then return nil, safeErr end

    local fn, err = loadstring(src)
    if not fn then
        return nil, "Lua syntax error:\n" .. tostring(err)
    end
    if setfenv then
        local envOk, envErr = pcall(setfenv, fn, {})
        if not envOk then return nil, "Sandbox error:\n" .. tostring(envErr) end
    end
    local ok, result = pcall(fn)
    if not ok then
        return nil, "Runtime error:\n" .. tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "Expected a table, got " .. type(result)
    end

    local serializable, serialErr = validateSerializable(result, "root", 1, {}, { nodes = 0 })
    if not serializable then return nil, serialErr end

    local zoneCount = 0
    local totalChunkCells = 0
    for k, v in pairs(result) do
        zoneCount = zoneCount + 1
        if zoneCount > IMPORT_MAX_ZONES then return nil, "Import contains too many zones" end
        if type(k) ~= "string" then
            return nil, "Zone keys must be strings, got " .. type(k)
        end
        if k == "" or #k > 128 or k:find("[%c]") then
            return nil, "Zone keys must contain 1-128 printable bytes"
        end
        if type(v) ~= "table" then
            return nil, "Zone '" .. tostring(k) .. "' must be a table"
        end
        local fieldCount = 0
        for _ in pairs(v) do fieldCount = fieldCount + 1 end
        if fieldCount > IMPORT_MAX_FIELDS then return nil, "Zone '" .. k .. "' has too many fields" end
        if v.points ~= nil then
            if type(v.points) ~= "table" then
                return nil, "Zone '" .. k .. "'.points must be a table"
            end
            local pointCount = 0
            for pointKey in pairs(v.points) do
                if type(pointKey) ~= "number" or pointKey < 1 or pointKey ~= math.floor(pointKey) then
                    return nil, "Zone '" .. k .. "'.points must be an array"
                end
                pointCount = pointCount + 1
            end
            if pointCount ~= #v.points then return nil, "Zone '" .. k .. "'.points must be contiguous" end
            if pointCount > IMPORT_MAX_POINTS then return nil, "Zone '" .. k .. "' has too many rectangles" end
            for i, p in ipairs(v.points) do
                if type(p) ~= "table" or #p ~= 4 then
                    return nil, "Zone '" .. k .. "'.points[" .. i .. "] must be {x1,y1,x2,y2}"
                end
                local rectFieldCount = 0
                for rectKey in pairs(p) do
                    if type(rectKey) ~= "number" or rectKey < 1 or rectKey > 4
                        or rectKey ~= math.floor(rectKey) then
                        return nil, "Zone '" .. k .. "'.points[" .. i .. "] has invalid fields"
                    end
                    rectFieldCount = rectFieldCount + 1
                end
                if rectFieldCount ~= 4 then
                    return nil, "Zone '" .. k .. "'.points[" .. i .. "] must contain exactly four coordinates"
                end
                for j = 1, 4 do
                    if not finiteNumber(p[j]) or math.abs(p[j]) > IMPORT_MAX_COORD then
                        return nil, "Zone '" .. k .. "'.points[" .. i .. "][" .. j .. "] must be finite"
                    end
                end
                local x1, y1, x2, y2 = p[1], p[2], p[3], p[4]
                if x1 > x2 then x1, x2 = x2, x1 end
                if y1 > y2 then y1, y2 = y2, y1 end
                x1, y1, x2, y2 = math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2)
                local cells = (math.floor(x2 / CHUNK_SIZE) - math.floor(x1 / CHUNK_SIZE) + 1)
                    * (math.floor(y2 / CHUNK_SIZE) - math.floor(y1 / CHUNK_SIZE) + 1)
                totalChunkCells = totalChunkCells + cells
                if totalChunkCells > IMPORT_MAX_CHUNK_CELLS then
                    return nil, "Imported zone area is too large"
                end
                p[1], p[2], p[3], p[4] = x1, y1, x2, y2
            end
        end
    end

    return result, nil
end

-- ===========================================================================
-- CONSTRUCTOR
-- ===========================================================================

function UI:new(x, y, w, h, text, readOnly, onImport)
    local o = ISCollapsableWindowJoypad:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.initialText = text or ""
    o.readOnly = readOnly
    o.onImport = onImport
    o.backgroundColor = {
        r = 0,
        g = 0,
        b = 0,
        a = 0.8
    }
    o.borderColor = {
        r = 0.4,
        g = 0.4,
        b = 0.4,
        a = 1
    }
    o.width = w
    o.height = h
    o.anchorLeft = true
    o.anchorRight = true
    o.anchorTop = true
    o.anchorBottom = true
    o.fontHgt = getTextManager():getFontFromEnum(UIFont.Small):getLineHeight()
    o.lineNumber = 30
    return o
end

-- ===========================================================================
-- INITIALISE  (builds all children — journal pattern)
-- ===========================================================================

function UI:initialise()
    ISCollapsableWindowJoypad.initialise(self)

    -- KEY FIX: tell the engine NOT to route key events through Lua first.
    -- ISCollapsableWindowJoypad sets wantKeyEvents=true which intercepts
    -- printable characters before they reach the Java text component.
    self:setWantKeyEvents(false)

    local btnWid = 160
    local btnHgt = math.max(FONT_HGT_SMALL + 3 * 2, 25)
    local padBot = 10
    local inset = 2

    -- Multiline entry — height = inset + lines*fontHgt + inset (journal pattern)
    local entryH = inset + self.lineNumber * self.fontHgt + inset
    self.entry = ISTextEntryBox:new(self.initialText, 10, 20, self.width - 20, entryH)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry:setMultipleLine(true)
    self.entry.javaObject:setMaxLines(self.lineNumber)
    self.entry.javaObject:setMaxTextLength(self.lineNumber * 200)
    self:addChild(self.entry)
    self.entry:focus()

    local bottom = self.entry:getBottom()

    -- Status label (import mode — shows validation errors)
    self.statusLbl = ISLabel:new(10, bottom + 6, FONT_HGT_SMALL + 2, "", 1, 0.4, 0.4, 1, UIFont.Small, true)
    self.statusLbl:initialise()
    self.statusLbl:instantiate()
    self:addChild(self.statusLbl)

    local btnY = bottom + 6

    -- Validate & Import button (import mode only)
    if not self.readOnly then
        self.importBtn = ISButton:new((self.width / 2) - btnWid - 5, btnY, btnWid, btnHgt, "Validate & Import", self,
            self.onImportClick)
        self.importBtn.internal = "IMPORT"
        self.importBtn:initialise()
        self.importBtn:instantiate()
        self.importBtn.borderColor = {
            r = 1,
            g = 1,
            b = 1,
            a = 0.1
        }
        self:addChild(self.importBtn)
    end

    -- Close / Cancel button
    local closeLabel = self.readOnly and "Close" or "Cancel"
    local closeX = self.readOnly and (self.width / 2) - (btnWid / 2) or (self.width / 2) + 5
    self.closeBtn = ISButton:new(closeX, btnY, btnWid, btnHgt, closeLabel, self, self.onClose)
    self.closeBtn.internal = "CLOSE"
    self.closeBtn:initialise()
    self.closeBtn:instantiate()
    self.closeBtn.borderColor = {
        r = 1,
        g = 1,
        b = 1,
        a = 0.1
    }
    self:addChild(self.closeBtn)

    -- Fit window height to content (journal pattern)
    self:setHeight(self.closeBtn:getBottom() + padBot)
end

-- ===========================================================================
-- CALLBACKS
-- ===========================================================================

function UI:onClose()
    if UI.activeInstance == self then UI.activeInstance = nil end
    self:setVisible(false)
    self:removeFromUIManager()
end

function UI:onImportClick()
    if not self.onImport then
        return
    end
    local ok, err = self.onImport(self.entry:getText())
    if ok == "pending" then
        self.pendingImportRequestId = err
        self.statusLbl.name = "Import sent; waiting for server confirmation..."
        self.statusLbl.r, self.statusLbl.g, self.statusLbl.b = 0.9, 0.75, 0.25
        if self.importBtn and self.importBtn.setEnable then self.importBtn:setEnable(false) end
    elseif ok then
        self:onClose()
    else
        self.statusLbl.name = "Error: " .. (err or "unknown"):gsub("\n", "  ")
        self.statusLbl.r, self.statusLbl.g, self.statusLbl.b = 1.0, 0.3, 0.3
    end
end

function UI.onReplaceZonesResult(data)
    local win = UI.activeInstance
    if not win or type(data) ~= "table" or type(win.pendingImportRequestId) ~= "string"
        or data.requestId ~= win.pendingImportRequestId then return end
    win.pendingImportRequestId = nil
    if data.ok == true then
        win:onClose()
        return
    end
    if win.importBtn and win.importBtn.setEnable then win.importBtn:setEnable(true) end
    win.statusLbl.name = "Server rejected the import: " .. tostring(data.reason or "unknown error")
    win.statusLbl.r, win.statusLbl.g, win.statusLbl.b = 1.0, 0.3, 0.3
end

function UI:onKeyPressed(key)
    -- Only handle Escape — all other keys should flow to the Java text component.
    -- setWantKeyEvents(false) in initialise() is the primary fix; this is a fallback.
    if key == Keyboard.KEY_ESCAPE then
        self:onClose()
    end
end

-- ===========================================================================
-- RENDER
-- ===========================================================================

function UI:prerender()
    self.pinButton:setVisible(false)
    self.collapseButton:setVisible(false)
    self:drawRect(0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g,
        self.backgroundColor.b)
    self:drawRectBorder(0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g,
        self.borderColor.b)
end

-- ===========================================================================
-- OPEN
-- ===========================================================================

function UI:open(readOnly)
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w = math.min(860, sw - 40)
    local h = math.min(580, sh - 40)
    local mx = math.floor((sw - w) / 2)
    local my = math.floor((sh - h) / 2)

    local uiRef = self
    local text = self:buildExportString()

    local onImport = not readOnly and function(src)
        local data, err = uiRef:parseImportString(src)
        if err then
            return false, err
        end
        local requestId = string.format("PZI-%s-%s", tostring(getTimestampMs()), tostring(ZombRand(0, 1000000)))
        local outcome = type(Core.replaceZones) == "function" and Core.replaceZones(data, requestId) or false
        if outcome == "pending" then return "pending", requestId end
        if outcome ~= true then
            return false, "The imported zone data could not be persisted"
        end
        return true, nil
    end or nil

    local win = UI:new(mx, my, w, h, text, readOnly, onImport)
    UI.activeInstance = win
    win:initialise()
    win:setTitle(readOnly and "Zone Data — Export" or "Zone Data — Edit / Import")
    win:addToUIManager()
    win:setVisible(true)
end
