-- Lascivious Factions System - membership-aware claim permissions (client side).
--
-- Inside a faction claim, only members of the owning faction may build, place,
-- pick up, scrap, disassemble, destroy or craft; non-members are blocked.
-- Container loot is handled separately by the vanilla SafeHouse the server
-- creates per claim (see LFS_Server.lua), so it is NOT touched here.
--
-- We mirror PhunZones' own override pattern (features/building.lua, movables.lua,
-- nodestroy.lua) but layer a membership check on top instead of reading a blanket
-- zone flag -- that is why LFS_Claims.lua no longer emits the
-- nobuilding/nopickup/etc. flags (they would block our own members too).
--
-- CAVEAT: like PhunZones (and our raid-PVP toggle), these are client-side and
-- therefore advisory -- a modified client could bypass them. True server-side
-- enforcement of build/craft is not available without deeper hooks; this matches
-- the mod's existing trust model.

require "LFS_Shared"
require "LFS_Claims"
require "LFS_Localization"

local FF = LasciviousFactionsSystem

-- Show the standard "you can't do that here" feedback and deny the action.
local function deny(character)
    if character and character.setHaloNote then
        character:setHaloNote(FF.tr("This is another faction's claim."), 255, 255, 0, 300)
    end
    return false
end

-- May this character exercise `perm` on the given square? Nil square -> allow
-- (let the underlying action decide). Reads FF.playerCanActAt.
--
-- Admins bypass every claim permission check everywhere, not just their own faction's
-- claims -- FF.isLocalAdmin() (client/LFS_Admin.lua) is a check of the
-- LOCAL client's own access level, and PZ only ever validates build/craft/destroy
-- actions for the locally-controlled character on each client, so this always asks
-- about the right person.
local function allowedAt(character, square, perm)
    if not (character and square) then return true end
    if FF.isLocalAdmin and FF.isLocalAdmin() then return true end
    local user = character.getUsername and character:getUsername()
    if not user then return true end
    local ok = FF.playerCanActAt(user, square:getX(), square:getY(), perm)
    return ok
end

-- Wrap `method` on `class` with a guard that resolves the acting character +
-- square via the supplied `resolve(self, ...)` -> character, square, and gates it
-- on `perm` ("build" / "move"). When the character's role lacks `perm` on that
-- claim the action is blocked; otherwise we chain to the original. Each install is
-- guarded so a missing class/method just logs.
local function guard(className, class, method, resolve, perm)
    if not (class and type(class[method]) == "function") then
        FF.log("permissions: " .. className .. ":" .. method .. " not found; skipping")
        return
    end
    local old = class[method]
    class[method] = function(self, ...)
        local ok, character, square = pcall(resolve, self, ...)
        if ok and character and square and not allowedAt(character, square, perm) then
            return deny(character)
        end
        return old(self, ...)
    end
    FF.log("permissions: hooked " .. className .. ":" .. method)
end

-- Install all hooks. Deferred to OnGameStart so PhunZones has already installed
-- its own overrides and we chain on top of them.
local function installHooks()
    if FF._permissionHooksInstalled then return end
    ------------------------------------------------------------------ building
    -- self.player is a player index for build objects. Gated on the "build" perm.
    guard("ISBuildingObject", _G.ISBuildingObject, "isValid", function(self, square)
        return getSpecificPlayer(self.player), square
    end, "build")
    guard("ISBuildIsoEntity", _G.ISBuildIsoEntity, "isValid", function(self, square)
        return getSpecificPlayer(self.player), square
    end, "build")
    guard("ISBuildingObject", _G.ISBuildingObject, "tryBuild", function(self, x, y, z)
        local character = getSpecificPlayer(self.player)
        local cell = getCell and getCell()
        local square = cell and z and cell:getGridSquare(x, y, z) or nil
        return character, square
    end, "build")

    ------------------------------------------------------------------ movables
    -- ISMoveablesAction:isValid() -- place / pickup / scrap, all on the character's
    -- current square. Gated on the "move" perm.
    guard("ISMoveablesAction", _G.ISMoveablesAction, "isValid", function(self)
        return self.character, self.character and self.character:getSquare()
    end, "move")

    ------------------------------------------------------------- destroy/scrap
    guard("ISDestroyStuffAction", _G.ISDestroyStuffAction, "isValid", function(self)
        return self.character, self.character and self.character:getSquare()
    end, "move")
    guard("ISDestroyCursor", _G.ISDestroyCursor, "isValid", function(self, square)
        return self.character, square
    end, "move")

    ------------------------------------------------------------------- crafting
    -- B42 has several craft action classes; hook every one that exists. Each has
    -- self.character; we gate by the character's current square on the "build" perm.
    local craftResolve = function(self)
        return self.character, self.character and self.character:getSquare()
    end
    for _, name in ipairs({
        "ISCraftAction", "ISCraftAnimAction", "ISHandcraftAction",
        "ISStartCraftProcessorAction",
    }) do
        guard(name, _G[name], "isValid", craftResolve, "build")
    end

    FF._permissionHooksInstalled = true
    FF.log("permissions: hook installation complete")
end

if FF._permissionGameStartHook then Events.OnGameStart.Remove(FF._permissionGameStartHook) end
FF._permissionGameStartHook = installHooks
Events.OnGameStart.Add(installHooks)
