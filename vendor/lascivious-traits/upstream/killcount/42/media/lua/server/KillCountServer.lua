

if isClient() then return end

KCServer = KCServer or {}

function KCServer.OnClientCommand(mod, command, player, args)
    if KCShared.Verbose then print("KCServer.OnClientCommand("..mod.." , "..command.." , "..tostring(player or "nil").." , args?)") end
    if mod ~= KCShared.Key then return end

    if command == player:getUsername() then
        local currentBufferClientTime = args.lastUpdateTime
        local gmd = ModData.get(KCShared.Key)
        
        if currentBufferClientTime then --avoid update if the buffer is older than last taken into account
            local pmd = gmd[command]
            if pmd and pmd.lastUpdateTime and pmd.lastUpdateTime > currentBufferClientTime then
                return--bypass the update it is older than previous one
            end
        end
        
        if gmd then
            gmd[command] = args--override last values
        end
        
        if SandboxVars.KillCount.shareOnServer then
            ModData.transmit(KCShared.Key);--share with all subscribed clients --TODO limit server emition frequency
        end
    end
end
Events.OnClientCommand.Add(KCServer.OnClientCommand)

--we use Global Mod Data to save and load, let's log it at load time for debug
function KCServer.OnInitGlobalModData()
    --clear on sandbox option change
    if not SandboxVars.KillCount.shareOnServer then
        ModData.remove(KCShared.Key)
    elseif not SandboxVars.KillCount.keepTrackOfDead then
        local gmd = ModData.getOrCreate(KCShared.Key)--create for valid register of clients
        local toRemove = {}
        for userName,data in pairs(gmd) do
            if string.find(userName,'%.') then
                table.insert(toRemove,userName)
            end
        end
        for i=1, #toRemove do
            gmd[toRemove[i]] = nil
        end
    else
        ModData.getOrCreate(KCShared.Key)--create for valid register of clients
    end

    if KCServer.Verbose then print ("KCServer.OnInitGlobalModData "..tab2str(ModData.get(KCShared.Key))) end
end

Events.OnInitGlobalModData.Add(KCServer.OnInitGlobalModData)--this is used in solo: todo remove?


function KCServer.OnCharacterDeath(character)
    if character.getUsername then
        local gmd = ModData.get(KCShared.Key)
        if gmd then
            local name = character:getUsername()
            local pmd = gmd[name]
            if pmd then
                gmd[name] = nil--disconnect from db
                if SandboxVars.KillCount.keepTrackOfDead then
                    local deadName = KCServer.geNextDeadName(gmd,name)
                    if deadName then
                        gmd[deadName] = pmd
                    end
                end
                if SandboxVars.KillCount.shareOnServer then
                    ModData.transmit(KCShared.Key);--share with all subscribed clients someone is dead
                end
            end
        end
    end
end

--this seems not to be called when a player is killed by a horde spawned on the same client side.
Events.OnCharacterDeath.Add(KCServer.OnCharacterDeath)

local strsub = string.sub
local tonumber = tonumber
local strlen = string.len
function KCServer.geNextDeadName(gmd,username)
    local prefix = username..'.'
    local length = strlen(prefix)
    local number = 1
    for name,pmd in pairs(gmd) do
        local subname = strsub(name,1,length)
        if subname==prefix then
            local suffix = strsub(name,length+1,-1)
            if suffix then
                local existingNumber = tonumber(suffix)
                if existingNumber and existingNumber >= number then
                    number = existingNumber + 1
                end
            end
        end
    end
    return prefix..number
end

