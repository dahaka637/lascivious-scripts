-- Client side of admin storage capacities: applies live broadcasts and
-- re-stamps capacities whenever the inventory backpack row rebuilds
-- (the client re-derives vehicle container capacity from the part item
-- on every VehiclePartItem packet, world containers from sprite props).
require "Aegis_Capacity"
require "ISUI/ISInventoryPage"

-- position registry: the loot panel in MP can show a synced PROXY
-- container instead of the object's own container (the
-- object was provably set to 500, the panel stayed at 100). The registry
-- lets the refresh wrapper stamp whatever instance the panel really uses
local capacityBySquare = {}

local function squareKey(x, y, z)
    return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

-- shared square apply used by the broadcast AND the direct reply
local function applySquareCapacity(x, y, z, value)
    local applied = 0
    pcall(function()
        local square = getCell():getGridSquare(x, y, z)
        if not square then
            print("[Aegis] capacity apply: square not loaded client side " .. tostring(x) .. "," .. tostring(y))
            return
        end
        local function apply(list)
            for i = 0, list:size() - 1 do
                local obj = list:get(i)
                if obj and obj.getContainerCount and obj:getContainerCount() > 0 then
                    obj:getModData().aegisCapacity = value
                    AegisCapacity.applyObject(obj)
                    applied = applied + 1
                end
            end
        end
        apply(square:getObjects())
        apply(square:getSpecialObjects())
    end)
    capacityBySquare[squareKey(x, y, z)] = value
    print("[Aegis] capacity apply: " .. tostring(applied) .. " container object(s) at "
        .. tostring(x) .. "," .. tostring(y) .. " set to " .. tostring(value))
    return applied
end

-- the engine clamps capacity ON READ: ItemContainer.getCapacity returns
-- min(field, 100) for world containers, min(field, 50) for bags, only
-- vehicles get 1000 (the bytecode shows it, explains "stuck at 100" no matter
-- what was stored). The class metatable override lifts the clamp for
-- stamped containers at every Lua call site: display, drag checks and
-- transfer validation all go through these three methods
-- the inventory UI calls getCapacity many times per frame, the stamp
-- lookup walks parent/modData/square every time: cached per container
-- for a second (false marks "no stamp", nil means "not looked up yet")
local capCache = {}
local capCacheReset = 0

local function stampedCapacity(c)
    local now = getTimestampMs()
    if now > capCacheReset then
        capCache = {}
        capCacheReset = now + 1000
    end
    local hit = capCache[c]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local ok, v = pcall(function()
        -- floor loot shares the square with stamped objects, keep vanilla
        if c:getType() == "floor" then return nil end
        -- vehicle parts: the engine re-derives trunk capacity from the
        -- part item on every sync, the modData stamp is the constant
        local vp = c:getVehiclePart()
        if vp then
            local s = vp:getModData().aegisCapacity
            if s then return tonumber(s) end
            return nil
        end
        -- a container living inside an item is a bag: its stamp sits on
        -- that item and nowhere else. Checked BEFORE the parent on purpose,
        -- otherwise a bag inherits the stamp of whoever holds it, and the
        -- carry weight stamp on a player would resize every bag they wear
        local item = c:getContainingItem()
        if item then
            local s = item:getModData().aegisCapacity
            if s then return tonumber(s) end
            return nil
        end
        local parent = c:getParent()
        if parent and parent.hasModData and parent:hasModData() then
            local s = parent:getModData().aegisCapacity
            if s then return tonumber(s) end
        end
        local sq = c:getSourceGrid()
        if sq then
            return capacityBySquare[squareKey(sq:getX(), sq:getY(), sq:getZ())]
        end
        return nil
    end)
    if not ok then v = nil end
    capCache[c] = v or false
    return v
end

local meta = __classmetatables[ItemContainer.class].__index
local javaGetCapacity = meta.getCapacity
meta.getCapacity = function(c)
    return stampedCapacity(c) or javaGetCapacity(c)
end

-- The engine adds the Organized / Disorganized bonus ON TOP of the plain
-- capacity, and it does that INSIDE getEffectiveCapacity (bytecode of
-- ItemContainer.getEffectiveCapacity: cap = getCapacity(), then for
-- ORGANIZED max(cap * 1.3, cap + 1), for DISORGANIZED max(cap * 0.7, 1),
-- skipped for a character inventory, a corpse and the floor).
-- A stamp that short circuits that method therefore SWALLOWED the trait:
-- on every container an admin had ever given a capacity, Organized
-- silently stopped working, and because the stamp lives in modData it
-- survived saves and backup restores. The stamp replaces
-- the base capacity, the trait still rides on top of it
local function traitAdjusted(c, chr, cap)
    if not chr or not cap then return cap end
    local ok, res = pcall(function()
        if c:getType() == "floor" then return cap end
        local parent = c:getParent()
        if parent and (instanceof(parent, "IsoGameCharacter") or instanceof(parent, "IsoDeadBody")) then
            return cap
        end
        if chr:hasTrait(CharacterTrait.ORGANIZED) then
            return math.floor(math.max(cap * 1.3, cap + 1))
        end
        if chr:hasTrait(CharacterTrait.DISORGANIZED) then
            return math.floor(math.max(cap * 0.7, 1))
        end
        return cap
    end)
    if ok and res then return res end
    return cap
end

local javaGetEffective = meta.getEffectiveCapacity
meta.getEffectiveCapacity = function(c, chr)
    local cap = stampedCapacity(c)
    if cap then return traitAdjusted(c, chr, cap) end
    return javaGetEffective(c, chr)
end
-- Every java overload starts with the character: (chr, item), (chr, w)
-- and (chr, w, w). Any other shape matches none of them, and the
-- engine's resolver LEAKS its pooled MethodArguments on that path
-- (verified in the bytecode of MultiLuaJavaInvoker.call: the invalid
-- branch jumps out of the loop without putting them back). This override
-- sits in the class metatable and therefore sees the calls of vanilla
-- and of every other mod, so only a shape we have checked is ever
-- forwarded, the rest is answered here
local javaHasRoomFor = meta.hasRoomFor

local function isCharacter(a)
    if a == nil then return false end
    local ok, res = pcall(instanceof, a, "IsoGameCharacter")
    return ok and res == true
end

local function weightOf(thing)
    if type(thing) == "number" then return thing end
    local add = 0
    if thing then pcall(function() add = thing:getUnequippedWeight() end) end
    return add
end

meta.hasRoomFor = function(c, a, b, extra)
    local cap = stampedCapacity(c)
    if not cap then
        if isCharacter(a) and b ~= nil then
            if extra == nil then return javaHasRoomFor(c, a, b) end
            return javaHasRoomFor(c, a, b, extra)
        end
        local held, jcap = 0, 0
        pcall(function() held = c:getCapacityWeight() end)
        pcall(function()
            -- with a known character the EFFECTIVE capacity is the right
            -- yardstick, it carries Organized and Disorganized
            if isCharacter(a) then jcap = javaGetEffective(c, a) else jcap = javaGetCapacity(c) end
        end)
        return (held + weightOf(b == nil and a or b)) <= jcap
    end
    -- stamped container: the weight to add is the second argument, either
    -- a number or the item itself, matching the java overloads. The trait
    -- rides on top of the stamp, same rule the engine applies
    local eff = isCharacter(a) and traitAdjusted(c, a, cap) or cap
    local held = 0
    pcall(function() held = c:getCapacityWeight() end)
    return (held + weightOf(b == nil and a or b)) <= eff
end

AegisCapacityClient = AegisCapacityClient or {}
require "TimedActions/ISBaseTimedAction"

-- describe a container so the server can resolve its own instance
function AegisCapacityClient.containerSpec(c)
    local spec = nil
    pcall(function()
        local part = c:getVehiclePart()
        if part then
            spec = { kind = "veh", id = part:getVehicle():getId(), part = part:getId() }
            return
        end
        local chr = c:getCharacter()
        if chr then
            -- "== chr:getInventory()" is unreliable: Kahlua can hand back
            -- a fresh wrapper on every call, so the identity check missed
            -- even the ROOT inventory sometimes (main
            -- inventory transfers crashed too). A container's own
            -- containingItem is nil only for the root inventory, never
            -- for a bag, that is a property check instead of an identity
            -- one and holds regardless of wrapper instances
            local bag = c:getContainingItem()
            if bag then
                spec = { kind = "bag", itemId = bag:getID() }
            else
                spec = { kind = "player" }
            end
            return
        end
        local sq = nil
        local parent = c:getParent()
        if parent and parent.getSquare then sq = parent:getSquare() end
        if not sq then sq = c:getSourceGrid() end
        if sq then
            spec = { kind = "obj", x = sq:getX(), y = sq:getY(), z = sq:getZ(), type = c:getType() }
        end
    end)
    return spec
end

-- server confirmation path: our own inventory needs the local remove,
-- the add side arrives via the regular container item sync
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" or command ~= "adminMoveItem" then return end
    if not args then return end
    if args.removeId then
        pcall(function()
            local inv = getPlayer():getInventory()
            local item = inv:getItemWithID(args.removeId)
            if item then inv:Remove(item) end
        end)
    end
    if args.ok == false then
        -- mirror the refusal into the client log: the move fails silently
        -- otherwise, the item simply stays put and the player has nothing
        -- to report but "it does not work"
        print("[Aegis] server refused the container move: " .. tostring(args.reason))
        return
    end
    -- make the moved item show up right away in both panels
    pcall(function()
        getPlayerInventory(0):refreshBackpacks()
        getPlayerLoot(0):refreshBackpacks()
    end)
end)

-- when a transfer action turns invalid mid-run the queue clears and the
-- character stops stowing; log every failing condition so
-- the exact culprit shows in the log
require "TimedActions/ISInventoryTransferAction"

-- hijacked phases for aegisServerMove actions: no vanilla transaction
-- (the server rejected those), no rejection polling, the
-- finish sends the Aegis move command instead of the vanilla transfer
-- Vanilla's own duration formula, rebuilt from ISInventoryTransferAction
-- :new (client/TimedActions/ISInventoryTransferAction.lua:788-851).
-- Needed because in MULTIPLAYER vanilla throws its result away again two
-- lines later (":853-856", maxTime = -1) and waits for the server to send
-- the real duration with the transaction. A hijacked Aegis move has no
-- vanilla transaction, so that number never arrives and the action would
-- hang. This reproduces what vanilla would have used, traits included,
-- instead of inventing one: the old code fell back to a floor of 25 ticks
-- for everything, which made a plastic bag take about a second and
-- silently dropped Dexterous and All Thumbs
local function vanillaTransferTime(self)
    local time = 120
    local ok = pcall(function()
        local chr, src, dest = self.character, self.srcContainer, self.destContainer
        if chr:isTimedActionInstant() then time = 1 return end
        if self.item and self.item:isFavorite() and not dest:isInCharacterInventory(chr) then
            time = 0
            return
        end
        local delta = 1.0
        if src == chr:getInventory() then
            if dest:isInCharacterInventory(chr) then
                delta = dest:getCapacityWeight() / dest:getMaxWeight()
            else
                time = 50
            end
        elseif not src:isInCharacterInventory(chr) then
            if dest:isInCharacterInventory(chr) then time = 50 end
        end
        if delta < 0.4 then delta = 0.4 end
        if self.item then
            local w = self.item:getActualWeight()
            if w > 3 then w = 3 end
            time = time * w * delta
        end
        if dest:getType() == "floor" then
            if src == chr:getInventory() then
                time = time * 0.1
            elseif not src:isInCharacterInventory(chr) then
                time = time * 0.2
            end
        end
        if chr:hasTrait(CharacterTrait.DEXTROUS) then time = time * 0.5 end
        if chr:hasTrait(CharacterTrait.ALL_THUMBS) or chr:isWearingAwkwardGloves() then
            time = time * 2.0
        end
    end)
    if not ok then return 50 end
    return math.max(0, math.floor(time))
end

local prevTransferStart = ISInventoryTransferAction.start
function ISInventoryTransferAction:start()
    if self.aegisServerMove then
        -- vanilla MP transfers run open ended and get finished by the
        -- transaction done signal, which this action skips: give it a
        -- real duration or it loads forever. Time first,
        -- the anim call must never block it
        local time = tonumber(self.maxTime) or -1
        -- exactly -1 and anything absurd needs a number of our own, a real
        -- one (0 included, that means instant and has to stay instant)
        if time < 0 or time > 200 then
            time = vanillaTransferTime(self)
        end
        self.maxTime = time
        pcall(function() self.action:setTime(time) end)
        pcall(function() self:setActionAnim("TransferItemOnSelf") end)
        return
    end
    return prevTransferStart(self)
end

local prevTransferUpdate = ISInventoryTransferAction.update
function ISInventoryTransferAction:update()
    if self.aegisServerMove then return end
    return prevTransferUpdate(self)
end

local prevTransferPerform = ISInventoryTransferAction.perform
function ISInventoryTransferAction:perform()
    if self.aegisServerMove then
        if not self.aegisSent then
            self.aegisSent = true
            pcall(function()
                sendClientCommand(getPlayer(), "AegisAdmin", "adminMoveItem", {
                    itemId = self.item:getID(), src = self.aegisSrc, dest = self.aegisDest,
                })
            end)
        end
        -- full vanilla completion, otherwise the java action loops and
        -- perform fires every frame
        pcall(function()
            self.action:stopTimedActionAnim()
            self.action:setLoopedAction(false)
            if isClient() then self.action:setWaitForFinished(false) end
        end)
        ISBaseTimedAction.perform(self)
        self.started = false
        return
    end
    return prevTransferPerform(self)
end

-- Who actually said no? We are not the only mod on this hook, and a NO that
-- came from somebody else is never ours to overrule. Vanilla's own refusal
-- on this road is the transaction consistency check
-- (ISInventoryTransferAction.lua:49, a java global on LuaManager), and that
-- one is exactly the flaw the rescue below works around. So: consistency
-- false means vanilla refused and we may step in, consistency TRUE means
-- vanilla was content and the no came from another guard on the same hook.
-- Knox Claim is the live example, it refuses looting a claimed trunk right
-- here, silently through a halo text, with no admin exemption
-- (KC_Protect.lua:50 -> KnoxClaim.vehicleRight). Overruling that would have
-- handed every stamped trunk to anyone.
-- Unreadable counts as NOT refused: an override has to be proven, not
-- assumed, same rule as everywhere else in this mod
local function vanillaRefused(act)
    local refused = false
    local ok = pcall(function()
        refused = not isItemTransactionConsistent(act.item, act.srcContainer,
            act.destContainer, nil, act.character)
    end)
    return ok and refused
end

local prevTransferValid = ISInventoryTransferAction.isValid
function ISInventoryTransferAction:isValid()
    -- the committed hijack stays alive against vanilla's instance quirk. It
    -- is safe to hold it here because the DECISION below already proved that
    -- no foreign guard objected at the time it was taken
    if self.aegisServerMove then return true end
    local ok = prevTransferValid(self)
    -- vehicle destinations pass the client validation, then the server
    -- transaction rejects the modded trunk capacity without any log and
    -- the item snaps back. Admin moves into vehicle
    -- containers go the Aegis road up front; world containers keep
    -- their proven flow below untouched
    if ok and isClient() then
        local hijacked = false
        pcall(function()
            if not (self.destContainer and self.destContainer:getVehiclePart()) then return end
            -- ONLY a destination that actually carries an Aegis stamp. The
            -- whole reason to leave the vanilla road is that the server
            -- transaction refuses a MODDED capacity; without a stamp there
            -- is no modded capacity and nothing to work around, so vanilla
            -- keeps the move. This used to hijack whenever the mover was
            -- "not level none", which in B42 is EVERY player (the default
            -- level is "user"), so every trunk transfer of every player on
            -- the server took this detour. That is what made vehicle
            -- containers behave differently from every other container and
            -- what blocked ordinary players out of some modded trunks
            if stampedCapacity(self.destContainer) == nil then return end
            local srcSpec = AegisCapacityClient.containerSpec(self.srcContainer)
            local destSpec = AegisCapacityClient.containerSpec(self.destContainer)
            if srcSpec and destSpec then
                self.aegisServerMove = true
                self.aegisSrc = srcSpec
                self.aegisDest = destSpec
                hijacked = true
            end
        end)
        if hijacked then return true end
    end
    local admin = false
    if not ok then
        pcall(function()
            admin = Aegis.allowed(self.character)
            if not admin then
                -- resolve the level through the role registry like every
                -- other Aegis gate. The old test accepted anything that was
                -- not "" or "none", and B42 hands every normal player the
                -- level "user", so it was true for everyone
                local level = tostring(getAccessLevel and getAccessLevel() or ""):lower()
                admin = AegisShared.levelIsAdmin(level)
            end
        end)
        -- ORDINARY players need this road too, and only for a stamped
        -- destination. In MP the vanilla check ends in
        -- TransactionManager.isConsistent, which calls hasRoomFor and
        -- getEffectiveCapacity from JAVA and therefore never sees our lua
        -- override; on top of that ItemContainer.getCapacity clamps world
        -- containers to 100 on read. So an assigned capacity was visible
        -- but not usable past that clamp, and only admins had the rescue
        -- below: it looked like it worked on crates (default 50, so 100
        -- still felt like a win) and did nothing on counter tops and
        -- floating cabinets, which already sit at the clamp (player
        -- report). The server accepts this move from anyone as long as
        -- range, item and the STAMPED capacity check out (moveValidated),
        -- so opening the road for a stamped destination grants nothing
        -- the admin did not already grant by assigning that capacity
        if not admin then
            pcall(function() admin = stampedCapacity(self.destContainer) ~= nil end)
        end
    end
    -- a no we cannot attribute to vanilla belongs to another mod, and that
    -- one stands. Only in MP: vanilla runs its consistency check behind
    -- isClient() (ISInventoryTransferAction.lua:44), so solo has no such
    -- signal to read, and solo has no other players to protect anyway. This
    -- keeps the single player behaviour exactly as it was
    if not ok and admin and isClient() and not vanillaRefused(self) then return ok end
    if not ok and admin then
        -- the vanilla check compares container INSTANCES against the
        -- nearby list; the loot panel proxies get rebuilt mid transfer
        -- and the queued action still holds the old instance: the log
        -- shows src/dest fine while the action dies anyway. The integrity
        -- conditions are re-checked directly instead
        local pass = false
        pcall(function()
            local item, src, dest = self.item, self.srcContainer, self.destContainer
            if item and src and dest and src ~= dest
                and not item:getIsCraftingConsumed()
                and (item:getContainer() == src or self:isAlreadyTransferred(item))
                and src:isRemoveItemAllowed(item)
                and dest:isItemAllowed(item)
                and dest:hasRoomFor(self.character, item) then
                pass = true
            end
        end)
        if pass then
            -- solo: the lua checks are the whole truth, let it run.
            -- MP: the vanilla flow would still die on the server side
            -- transaction,
            -- the Aegis server moves the item itself instead
            if not isClient() then return true end
            -- NEVER take the Aegis road into a character's own inventory.
            -- Reloading queues one ordinary transfer action per round
            -- (vanilla ISInventoryPaneContextMenu.transferIfNeeded:1926),
            -- and a carry weight stamp makes the player's own inventory a
            -- stamped container, so those rounds became eligible for the
            -- hijack. A hijacked round reports success from the action
            -- while the actual move depends on our server command, and a
            -- round that never lands makes the gun come up short: the
            -- player has to run extra reload animations to fill it
            -- (a 6 round gun needed 8 motions). Moves
            -- INTO a character never needed this road anyway, the vanilla
            -- transaction handles them
            local intoCharacter = false
            pcall(function()
                local parent = self.destContainer:getParent()
                intoCharacter = parent ~= nil and instanceof(parent, "IsoGameCharacter")
            end)
            if intoCharacter then return ok end
            -- hijack instead of replace: the action stays in the queue
            -- with its normal duration and animation, only its finish
            -- sends the Aegis server move (killing it here would clear
            -- the whole queue)
            local srcSpec = AegisCapacityClient.containerSpec(self.srcContainer)
            local destSpec = AegisCapacityClient.containerSpec(self.destContainer)
            if srcSpec and destSpec then
                if not self.aegisServerMove then
                    self.aegisServerMove = true
                    self.aegisSrc = srcSpec
                    self.aegisDest = destSpec
                end
                return true
            end
        end
    end
    return ok
end

-- rebuild the square registry from the synced object stamps whenever a
-- chunk loads: the registry used to live only for the session, after a
-- relog the loot panel proxies (no parent reachable) lost their values
-- while the display still showed the stamp (350 shown, ~110 usable)
Events.LoadGridsquare.Add(function(square)
    pcall(function()
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            if obj and obj:hasModData() and obj:getModData().aegisCapacity
                and obj.getContainerCount and obj:getContainerCount() > 0 then
                local value = tonumber(obj:getModData().aegisCapacity)
                if value then
                    capacityBySquare[squareKey(square:getX(), square:getY(), square:getZ())] = value
                end
            end
        end
    end)
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "AegisAdmin" then return end
    -- direct reply to the acting admin doubles as a local apply: the
    -- broadcast can race the reply, this way at least the actor is right
    if command == "containerCapacity" and args and args.ok and args.x then
        applySquareCapacity(args.x, args.y, args.z or 0, tonumber(args.value))
        return
    end
    if command ~= "capacityApply" or not args then return end
    local value = tonumber(args.value)
    if not value then return end
    if args.kind == "veh" then
        pcall(function()
            local car = getVehicleById(tonumber(args.id) or -1)
            local part = car and car:getPartById(tostring(args.part))
            if part and part:getItemContainer() then
                part:setContainerCapacity(value)
            end
        end)
    elseif args.kind == "obj" then
        -- apply the PACKET value and stamp locally: the modData sync for
        -- plain world objects lags or never arrives, waiting for it left
        -- the client at the sprite capacity (~100 on crates)
        applySquareCapacity(args.x, args.y, args.z, value)
    end
end)

-- Lazy client re-apply: the stamp arrives with the synced modData and
-- the engine may have overwritten the capacity since. This used to wrap
-- ISInventoryPage.refreshBackpacks, which put our file into the lua
-- stack of EVERY failure inside that vanilla function, so unrelated
-- engine crashes were reported as Aegis bugs. The pcall around it never
-- helped either: a java exception from the kahlua bridge is not a lua
-- error and passes straight through pcall. Now it runs on its own clock
-- and touches nobody else's call path
local function reapplyBackpacks(page)
    if not page or type(page.backpacks) ~= "table" then return end
    pcall(function()
        for _, btn in ipairs(page.backpacks) do
            local c = btn.inventory
            if c then
                local part = c:getVehiclePart()
                if part then
                    AegisCapacity.applyPart(part)
                else
                    local parent = c:getParent()
                    -- never the body container: its parent is the player,
                    -- and the carry weight stamp lives in exactly that
                    -- modData. Passing it to setCapacity made the engine
                    -- warn "over maximum" twice a second, 1229 lines in one
                    -- session. The body is served by the
                    -- getCapacity override, this setter is for the world
                    local onChar = false
                    pcall(function()
                        onChar = parent ~= nil and instanceof(parent, "IsoGameCharacter")
                    end)
                    if onChar then
                        parent = nil
                    end
                    if parent and parent:hasModData() and parent:getModData().aegisCapacity then
                        AegisCapacity.applyObject(parent)
                        -- the panel may hold a proxy instance: set it too
                        AegisCapacity.setField(c, tonumber(parent:getModData().aegisCapacity))
                    else
                        -- proxy without reachable parent: match by source square
                        local sq = c:getSourceGrid()
                        if sq then
                            AegisCapacity.setField(c, capacityBySquare[squareKey(sq:getX(), sq:getY(), sq:getZ())])
                        end
                    end
                    -- bags: the stamp travels in the item's modData, the
                    -- engine re-derives bag capacity from the item script
                    local item = c:getContainingItem()
                    if item then
                        AegisCapacity.setField(c, tonumber(item:getModData().aegisCapacity))
                    end
                end
            end
        end
    end)
end

-- twice a second is plenty: the stamp only has to win back the capacity
-- before the player reads the number off the container button
local reapplyNextAt = 0
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now < reapplyNextAt then return end
    reapplyNextAt = now + 500
    local ok, page = pcall(getPlayerInventory, 0)
    if ok and page then reapplyBackpacks(page) end
end)


-- right click on a bag in any inventory: set its capacity. Applied
-- locally plus stamped into the item modData (saves with the item, the
-- refresh wrapper re-applies whenever the bag is viewed)
Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    if playerNum ~= 0 then return end
    if not (Aegis.allowed(getPlayer()) and Aegis.canSee("tools")) then return end
    local bag = nil
    pcall(function()
        for _, entry in ipairs(items) do
            local item = entry
            if type(entry) == "table" then item = entry.items and entry.items[1] end
            if item and instanceof(item, "InventoryContainer") then
                bag = item
                break
            end
        end
    end)
    if not bag then return end
    local current = 0
    pcall(function() current = bag:getInventory():getCapacity() end)
    context:addOption(getText("UI_Aegis_Capacity"), nil, function()
        local prompt = AegisPrompt.show{
            title = getText("UI_Aegis_Capacity"),
            message = getText("UI_Aegis_CapacityPrompt", tostring(current)),
            confirmLabel = getText("UI_Aegis_Apply"),
            reasonRequired = true,
            onConfirm = function(page, textValue)
                local value = tonumber(textValue)
                if not value then return end
                value = math.floor(math.max(1, math.min(1000, value)))
                pcall(function()
                    bag:getModData().aegisCapacity = value
                    AegisCapacity.setField(bag:getInventory(), value)
                end)
                Aegis.logAction("tools", "Bag capacity set: " .. tostring(value))
                Aegis.showToast(getText("UI_Aegis_CapacitySet", tostring(value)))
            end,
        }
        pcall(function() prompt.entry:setOnlyNumbers(true) end)
    end)
end)
