-- Server-safe ladder geometry. It deliberately contains no UI or TimedAction APIs.
SubirEscalerasServer = SubirEscalerasServer or {}
local G = SubirEscalerasServer

local sprites = {
    industry_railroad_05_20="W", industry_railroad_05_21="N",
    industry_railroad_05_36="W", industry_railroad_05_37="N",
    industry_railroad_05_56="E", industry_railroad_05_57="S",
    industry_railroad_05_58="E", industry_railroad_05_59="S",
    location_sewer_01_32="W", location_sewer_01_33="N",
    location_sewer_01_48="E", location_sewer_01_49="S",
    carpentry_02_84="W", carpentry_02_85="N",
    carpentry_02_86="E", carpentry_02_87="S",
    advertising_01_6="W", advertising_01_14="N",
}

local flags = {
    N=IsoFlagType.climbSheetN, S=IsoFlagType.climbSheetS,
    E=IsoFlagType.climbSheetE, W=IsoFlagType.climbSheetW,
}
local keys = { N="ladderN", S="ladderS", E="ladderE", W="ladderW" }
local stepOff = { N={0,-1}, S={0,1}, E={1,0}, W={-1,0} }

function G.climbDir(object)
    if not object then return nil end
    local props = object:getProperties()
    if props then
        for dir, flag in pairs(flags) do if props:has(flag) then return dir end end
        for dir, key in pairs(keys) do if props:has(key) then return dir end end
    end
    local sprite = object:getSprite()
    local name = sprite and sprite:getName()
    if name and sprites[name] then return sprites[name] end
    if props and props:has("CustomName") then
        local custom = props:get("CustomName")
        if custom == "Ladder" or custom == "Ladders" then return "?" end
    end
    if name and string.find(string.lower(name), "ladder", 1, true) then return "?" end
    return nil
end

function G.findLadder(square)
    if not square then return nil end
    local objects = square:getObjects()
    for i=0, objects:size()-1 do
        local object = objects:get(i)
        local dir = G.climbDir(object)
        if dir then return object, dir end
    end
    return nil
end

local function standable(square)
    return square ~= nil and not square:isSolid() and not square:isSolidTrans()
        and square:TreatAsSolidFloor()
end

local function landing(x, y, z, dir, allowBlocked)
    if z < 0 or z > 31 then return nil end
    local cell = getCell()
    local exact = cell:getGridSquare(x, y, z)
    local candidates = {{0,0}}
    if stepOff[dir] then table.insert(candidates, stepOff[dir]) end
    for _, offset in pairs(stepOff) do table.insert(candidates, offset) end
    local fallback
    for _, offset in ipairs(candidates) do
        local square = cell:getGridSquare(x+offset[1], y+offset[2], z)
        if standable(square) then
            local same = offset[1] == 0 and offset[2] == 0
            local blocked = false
            if not same and exact then
                local ok, value = pcall(function() return exact:isSomethingTo(square) end)
                blocked = ok and value == true
            end
            if same or not blocked then return square end
            fallback = fallback or square
        end
    end
    if allowBlocked then return fallback end
    return nil
end

local function ladderEnd(x, y, z, up)
    local step, last = up and 1 or -1, z
    for _=1,31 do
        local nextZ = last + step
        if nextZ < 0 or nextZ > 31 then break end
        local square = getCell():getGridSquare(x, y, nextZ)
        if not square or not G.findLadder(square) then break end
        last = nextZ
    end
    return last
end

function G.target(ladderSquare, down, dir)
    local x, y, z0 = ladderSquare:getX(), ladderSquare:getY(), ladderSquare:getZ()
    local finish = ladderEnd(x, y, z0, not down)
    local first, last, step
    if down then first, last, step = finish, z0, 1
    else first, last, step = finish+1, z0+1, -1 end
    for z=first,last,step do
        local square = landing(x, y, z, dir, down)
        if square then return square end
    end
    return nil
end

return G
