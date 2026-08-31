
--- @sandbox BloodlustO_Control "Bloodlust Uncontrollable"
--- @class BloodlustUncontrollableSandboxOptions
---
---
--- @field TrackingOutburst boolean = true
--- Your character may turn to face a zombie. Consists of two phases:
--- 1. Movement Lock: You cannot move or look away.
--- 2. Idle: Your character will turn towards zombie when you stand still for a bit.
---
--- @field TrackingMinBloodlust number (0 to 100) = 40
--- Bloodlust level above which tracking may occur.
--- @field TrackingMaxBloodlust number (0 to 100) = 90
--- Bloodlust level at which max tracking chance is reached.
---
--- @field TrackingMaxChance number (0.0 to 100.0) = 10
--- Maximum chance for tracking to occur, tested every in-game minute.
---
--- The chance will start at 0% at min bloodlust, then increase linearly up to this value at max bloodlust.
---
--- @field TrackingRequiredIdleTime number (0.0 to 3600.0) = 1
--- How many real seconds since last player activity must pass for tracking to occur.
---
--- @field TrackingMinVisibleZombieTiles number (0.5 to 1000) = 8
--- Closest zombie that you can see must be this many tiles away from you for tracking to occur.
--- @field TrackingMinHiddenZombieTiles number (0.5 to 1000) = 4
--- Closest zombie that you cannot see must be this many tiles away from you for tracking to occur.
---
--- @field TrackingMovementLockSeconds number (0.0 to 3600.0) = 3
--- When tracking occurs, for how many real seconds you won't be able to control your character as it stands still, looking in direction of closest zombie.
---
--- @field TrackingMovementLockMinTilesFromZombie number (0.5 to 1000) = 7
--- Minimum tiles to closest zombie for tracking movement lock to happen.
---
--- @field TrackingStopIfZombieWithinTiles number (0.5 to 1000) = 3
--- Once tracking is active, if closest zombie is visible and is closer than this many tiles, don't track it.
---
--- @field TrackingMinMinutes number (1 to 10080) = 5
--- Minimum in-game minutes tracking may last.
--- @field TrackingMaxMinutes number (2 to 10080) = 60
--- Maximum in-game minutes tracking may last.
---
---
--- @field FollowingOutburst boolean = true
--- Your character may walk towards a zombie. Consists of two phases:
--- 1. Active: Any movement input moves you towards closest zombie.
--- 2. Idle: You move towards closest zombie if you're idle.
---
--- @field FollowingMinBloodlust number (0 to 100) = 80
--- Bloodlust level above which following may occur.
--- @field FollowingMaxBloodlust number (0 to 100) = 90
--- Bloodlust level at which max following chance is reached.
---
--- @field TrackingToFollowingMaxChance number (0.0 to 100.0) = 30
--- Maximum chance for Tracking to evolve into Following, tested every in-game minute, if player is moving.
---
--- The chance will start at 0% at min bloodlust, then increase linearly up to this value at max bloodlust.
---
--- @field TrackingToFollowingMinTilesFromVisibleZombie number (1.0 to 1000) = 12
--- Minimum distance visible zombie must be for Tracking to evolve into Following.
--- @field TrackingToFollowingMinTilesFromHiddenZombie number (1.0 to 1000) = 4
--- Minimum distance zombie you don't see must be for Tracking to evolve into Following.
---
--- @field FollowingActiveMinTilesFromZombie number (2.0 to 100) = 8
--- How many tiles away a closest zombie must be for active following phase.
---
--- @field FollowingActiveMinRealSeconds number (0.0 to 600.0) = 1.5
--- Minimum real seconds active phase may last for.
--- @field FollowingActiveMaxRealSeconds number (0.0 to 600.0) = 4
--- Maximum real seconds active phase may last for.
---
--- @field FollowingMovementAttemptMovesForSeconds number (0.01 to 60.0) = 0.1
--- During active phase, pressing a movement key will keep you moving towards closest zombie for this many seconds after the key is released.
---
--- @field FollowingIdleMinTilesFromZombie number (2.0 to 100) = 4
--- How many tiles away a closest zombie must be for idle following phase.
---
--- @field FollowingAfterInactivityMin number (0.03 to 600) = 2
--- Minimum real seconds you must be inactive for idle following to start.
--- @field FollowingAfterInactivityMax number (0.03 to 600) = 8
--- Maximum real seconds you must be inactive for idle following to start.
---
--- @field StartTrackingAfterInactivityWhenFollowing number (0 to 100) = 50
--- Once this percentage of inactivity time passes, the character will turn towards closest zombie.
---
--- @field FollowingMinIngameMinutes number (1 to 10080) = 10
--- Minimum in-game minutes following may last.
--- @field FollowingMaxIngameMinutes number (1 to 10080) = 30
--- Maximum in-game minutes following may last.
---
--- @field FollowingEndToTrackingChance number (0 to 100) = 10
--- Chance to immediately start Tracking when Following ends.
---
local DEFAULTS = {
    TrackingOutburst = true,
    TrackingMinBloodlust = 40,
    TrackingMaxBloodlust = 90,
    TrackingMaxChance = 10.0,
    TrackingRequiredIdleTime = 1.0,
    TrackingMinVisibleZombieTiles = 8.0,
    TrackingMinHiddenZombieTiles = 4.0,
    TrackingMovementLockSeconds = 3.0,
    TrackingMovementLockMinTilesFromZombie = 7.0,
    TrackingStopIfZombieWithinTiles = 3.0,
    TrackingMinMinutes = 5,
    TrackingMaxMinutes = 60,
    FollowingOutburst = true,
    FollowingMinBloodlust = 80,
    FollowingMaxBloodlust = 90,
    TrackingToFollowingMaxChance = 30.0,
    TrackingToFollowingMinTilesFromVisibleZombie = 12.0,
    TrackingToFollowingMinTilesFromHiddenZombie = 4.0,
    FollowingActiveMinTilesFromZombie = 8.0,
    FollowingActiveMinRealSeconds = 1.5,
    FollowingActiveMaxRealSeconds = 4.0,
    FollowingMovementAttemptMovesForSeconds = 0.1,
    FollowingIdleMinTilesFromZombie = 4.0,
    FollowingAfterInactivityMin = 2.0,
    FollowingAfterInactivityMax = 8.0,
    StartTrackingAfterInactivityWhenFollowing = 50,
    FollowingMinIngameMinutes = 10,
    FollowingMaxIngameMinutes = 30,
    FollowingEndToTrackingChance = 10,
}

SandboxVars = SandboxVars or {}
SandboxVars.BloodlustO_Control = SandboxVars.BloodlustO_Control or {}
local SB = SandboxVars.BloodlustO_Control

setmetatable(SB, {
    __index = DEFAULTS,
})

return SB
