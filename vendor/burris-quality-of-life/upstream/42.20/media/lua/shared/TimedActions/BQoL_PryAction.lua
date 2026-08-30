--[[
    Burris Quality of Life -- the prying timed action.

    Modelled on vanilla's ISUnbarricadeAction (shared/TimedActions), which is
    the closest thing the base game has: same anim, same crowbar sound, same
    zombie-attracting addSound().
]]

require "TimedActions/ISBaseTimedAction"
require "BQoL/BQoL_PryOutcome"

BQoL_PryAction = ISBaseTimedAction:derive("BQoL_PryAction")

--[[
    A real validity check, re-evaluated every tick.

    The action aborts if the target is destroyed or someone else unlocks the
    door mid-swing. (The mod this is modelled on returns true unconditionally,
    so its action happily continues against an object that no longer exists.)
]]
function BQoL_PryAction:isValid()
    if not self.target then return false end
    if not self.target:getSquare() then return false end

    --[[
        One shared implementation with Pry.classify, which is what offers the
        option in the first place. When the two disagree the action starts and
        aborts on its first tick, which reads in game as being cancelled --
        that is how the key-locked-door bug presented. This used to re-check
        only doors, so a window that was opened, barricaded or smashed
        mid-swing kept the action running.
    ]]
    if not BQoL.Pry.stillPriable(self.target, self.kind) then
        return false
    end

    -- The tool can be consumed or broken by something else mid-action.
    return self.tool ~= nil and not self.tool:isBroken()
end

function BQoL_PryAction:waitToStart()
    self.character:faceThisObject(self.target)
    return self.character:shouldBeTurning()
end

function BQoL_PryAction:update()
    self.character:faceThisObject(self.target)
    self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function BQoL_PryAction:start()
    self:setActionAnim("RemoveBarricade")
    self:setAnimVariable("RemoveBarricade", "CrowbarMid")
    self:setOverrideHandModels(self.tool, nil)

    local loopSound = BQoL.Pry.getSounds(self.garage)
    self.sound = self.character:playSound(loopSound)

    -- Levering a door open is noisy; zombies should hear it.
    addSound(self.character, self.character:getX(), self.character:getY(),
        self.character:getZ(), 12, 8)
end

local function stopSound(self)
    if not self.sound then return end
    self.character:getEmitter():stopSound(self.sound)
    self.sound = nil
end

function BQoL_PryAction:stop()
    stopSound(self)
    ISBaseTimedAction.stop(self)
end

function BQoL_PryAction:perform()
    stopSound(self)
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)
end

--[[
    Order matters here, and it is the difference between this feature working
    and doing nothing at all.

    The outcome is applied first and the endurance drain happens last. When
    Pry.tire sat between the roll and the outcome it took the whole action
    down with it: B42 had removed the endurance accessors it called, the
    resulting "Object tried to call nil" aborted complete() before the door
    was ever touched, and prying silently did nothing while looking like it
    had run. Nothing cosmetic belongs before the outcome.
]]
function BQoL_PryAction:complete()
    local playerObj = self.character
    local succeeded = BQoL.Pry.roll(playerObj, self.penalty)

    if succeeded then
        if isClient() then
            -- The server owns the world; ask it to open the door.
            self:sendToServer("prySuccess")
        else
            BQoL.Pry.applySuccess(self.target, playerObj, self.kind)
        end
    else
        -- Failure: complain, make noise, maybe break the glass.
        playerObj:Say(getText("IGUI_BQoL_PryFailed"))

        local _, breakSound = BQoL.Pry.getSounds(self.garage)
        playerObj:playSound(breakSound)
        addSound(playerObj, playerObj:getX(), playerObj:getY(), playerObj:getZ(), 10, 6)

        if isClient() then
            self:sendToServer("pryFailure")
        else
            BQoL.Pry.applyFailure(self.target, playerObj, self.kind)
        end
    end

    BQoL.Pry.tire(playerObj, self.kind == "window" and 0.05 or 0.07)
    return true
end

--[[
    Multiplayer: the client cannot mutate the world directly, so it sends the
    target's coordinates and the server resolves the object itself. Sending
    coordinates rather than an object reference is deliberate -- object handles
    do not survive the trip.
]]
function BQoL_PryAction:sendToServer(command)
    local square = self.target:getSquare()
    if not square then return end

    sendClientCommand(self.character, BQoL.COMMAND_MODULE, command, {
        x = square:getX(),
        y = square:getY(),
        z = square:getZ(),
        kind = self.kind,
    })
end

function BQoL_PryAction:getDuration()
    if self.character:isTimedActionInstant() then
        return 1
    end

    -- Stronger characters lever it faster; never below a third of the base.
    local base = self.kind == "window" and 150 or 190
    return math.max(base / 3, base - (BQoL.Pry.getStrength(self.character) * 8))
end

function BQoL_PryAction:new(character, target, kind, garage, tool, penalty)
    local o = ISBaseTimedAction.new(self, character)

    o.character = character
    o.target = target
    o.kind = kind
    o.garage = garage or false
    o.tool = tool
    o.penalty = penalty or 0
    o.maxTime = o:getDuration()

    return o
end
